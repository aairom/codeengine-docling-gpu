"""
DoclingGPU - IBM Code Engine Serverless Document Processing Application
Combines IBM Code Engine Serverless Fleets with Docling for GPU-accelerated document conversion.
"""

import os
import json
import uuid
import time
import subprocess
import threading
import logging
from datetime import datetime
from pathlib import Path
from flask import Flask, render_template, request, jsonify, send_file, redirect, url_for, flash
from werkzeug.utils import secure_filename
import requests

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)
app.secret_key = os.getenv('SECRET_KEY', 'docling-gpu-secret-key-change-in-prod')

# Configuration
UPLOAD_FOLDER = os.getenv('UPLOAD_FOLDER', '/tmp/uploads')
OUTPUT_FOLDER = os.getenv('OUTPUT_FOLDER', '/tmp/outputs')
LOCAL_INPUT_FOLDER = os.getenv('LOCAL_INPUT_FOLDER', './input')
LOCAL_OUTPUT_FOLDER = os.getenv('LOCAL_OUTPUT_FOLDER', './output')
MAX_CONTENT_LENGTH = int(os.getenv('MAX_CONTENT_LENGTH', str(500 * 1024 * 1024)))  # 500MB default

# IBM Cloud Code Engine / Fleet configuration
CE_PROJECT_ID = os.getenv('CE_PROJECT_ID', '')
CE_REGION = os.getenv('CE_REGION', 'eu-de')
CE_FLEET_TASK_STORE = os.getenv('CE_FLEET_TASK_STORE', 'fleet-task-store')
CE_FLEET_SUBNETPOOL = os.getenv('CE_FLEET_SUBNETPOOL', 'fleet-subnetpool')
CE_INPUT_STORE = os.getenv('CE_INPUT_STORE', 'fleet-input-store')
CE_OUTPUT_STORE = os.getenv('CE_OUTPUT_STORE', 'fleet-output-store')
CE_REGISTRY_SECRET = os.getenv('CE_REGISTRY_SECRET', 'fleet-registry-secret')

# Docling container images
DOCLING_GPU_IMAGE = os.getenv('DOCLING_GPU_IMAGE', 'quay.io/docling-project/docling-serve')
DOCLING_CPU_IMAGE = os.getenv('DOCLING_CPU_IMAGE', 'quay.io/docling-project/docling-serve-cpu')

# Processing mode
PROCESSING_MODE = os.getenv('PROCESSING_MODE', 'local')  # 'local', 'fleet-cpu', 'fleet-gpu'

# In-memory job store (use Redis in production)
jobs = {}

app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER
app.config['MAX_CONTENT_LENGTH'] = MAX_CONTENT_LENGTH

# Ensure directories exist
for folder in [UPLOAD_FOLDER, OUTPUT_FOLDER, LOCAL_INPUT_FOLDER, LOCAL_OUTPUT_FOLDER]:
    Path(folder).mkdir(parents=True, exist_ok=True)


def get_timestamp():
    """Get current timestamp for file naming."""
    return datetime.now().strftime('%Y%m%d_%H%M%S')


def create_job(job_id, files, output_dest, processing_mode, gpu_enabled=False):
    """Create a new processing job."""
    jobs[job_id] = {
        'id': job_id,
        'status': 'pending',
        'files': files,
        'output_dest': output_dest,
        'processing_mode': processing_mode,
        'gpu_enabled': gpu_enabled,
        'created_at': datetime.utcnow().isoformat(),
        'updated_at': datetime.utcnow().isoformat(),
        'progress': 0,
        'total_files': len(files),
        'processed_files': 0,
        'results': [],
        'errors': [],
        'fleet_id': None,
        'log': []
    }
    return jobs[job_id]


def update_job(job_id, **kwargs):
    """Update job status."""
    if job_id in jobs:
        jobs[job_id].update(kwargs)
        jobs[job_id]['updated_at'] = datetime.utcnow().isoformat()


def process_local(job_id, input_files, output_dir):
    """Process documents locally using Docling."""
    try:
        update_job(job_id, status='running', log=['Starting local Docling processing...'])

        from docling.document_converter import DocumentConverter, PdfFormatOption
        from docling.datamodel.base_models import InputFormat
        from docling.datamodel.pipeline_options import PdfPipelineOptions

        # Configure PDF pipeline options (OCR + table structure)
        pipeline_options = PdfPipelineOptions()
        pipeline_options.do_ocr = True
        pipeline_options.do_table_structure = True

        # Build converter accepting ALL Docling-supported formats
        converter = DocumentConverter(
            allowed_formats=[
                InputFormat.PDF,
                InputFormat.DOCX,
                InputFormat.PPTX,
                InputFormat.XLSX,
                InputFormat.HTML,
                InputFormat.MD,
                InputFormat.ASCIIDOC,
                InputFormat.CSV,
                InputFormat.IMAGE,
            ],
            format_options={
                InputFormat.PDF: PdfFormatOption(pipeline_options=pipeline_options)
            }
        )
        
        results = []
        timestamp = get_timestamp()
        
        for i, input_file in enumerate(input_files):
            try:
                file_name = Path(input_file).stem
                output_file = Path(output_dir) / f"{timestamp}_{file_name}.md"
                
                log_msg = f"Processing [{i+1}/{len(input_files)}]: {Path(input_file).name}"
                logger.info(log_msg)
                update_job(job_id, log=jobs[job_id]['log'] + [log_msg])
                
                start_time = time.time()
                result = converter.convert(input_file)
                markdown_content = result.document.export_to_markdown()
                elapsed = time.time() - start_time
                
                # Write output with metadata header
                with open(output_file, 'w', encoding='utf-8') as f:
                    f.write(f"---\n")
                    f.write(f"source: {Path(input_file).name}\n")
                    f.write(f"processed_at: {datetime.utcnow().isoformat()}\n")
                    f.write(f"processing_time_seconds: {elapsed:.2f}\n")
                    f.write(f"processing_mode: local\n")
                    f.write(f"---\n\n")
                    f.write(markdown_content)
                
                results.append({
                    'input': str(input_file),
                    'output': str(output_file),
                    'status': 'success',
                    'processing_time': elapsed
                })
                
                processed = i + 1
                progress = int((processed / len(input_files)) * 100)
                update_job(job_id, 
                          processed_files=processed,
                          progress=progress,
                          results=results)
                
                success_msg = f"✓ Completed {Path(input_file).name} in {elapsed:.2f}s → {output_file.name}"
                update_job(job_id, log=jobs[job_id]['log'] + [success_msg])
                
            except Exception as e:
                error_msg = f"✗ Error processing {Path(input_file).name}: {str(e)}"
                logger.error(error_msg)
                update_job(job_id, 
                          errors=jobs[job_id]['errors'] + [error_msg],
                          log=jobs[job_id]['log'] + [error_msg])
        
        final_status = 'completed' if not jobs[job_id]['errors'] else 'completed_with_errors'
        update_job(job_id, status=final_status, progress=100)
        logger.info(f"Job {job_id} completed. {len(results)} files processed.")
        
    except ImportError as e:
        error_msg = f"Docling not installed: {str(e)}. Install with: pip install docling"
        logger.error(error_msg)
        update_job(job_id, status='failed', errors=[error_msg])
    except Exception as e:
        error_msg = f"Processing failed: {str(e)}"
        logger.error(error_msg)
        update_job(job_id, status='failed', errors=[error_msg])


def generate_commands_jsonl(input_files, output_dir, num_threads=12):
    """Generate commands.jsonl for Code Engine fleet tasks."""
    commands = []
    for input_file in input_files:
        file_name = Path(input_file).name
        output_name = f"docling_{file_name}.md"
        cmd = {
            "cmds": ["docling"],
            "args": [
                "--num-threads", str(num_threads),
                f"/input/pdfs/{file_name}",
                "--output", f"/output/{output_name}"
            ]
        }
        commands.append(json.dumps(cmd))
    return '\n'.join(commands)


def launch_fleet(job_id, commands_jsonl_path, gpu_enabled=False, max_scale=8):
    """Launch a Code Engine serverless fleet."""
    try:
        fleet_uuid = str(uuid.uuid4())[:8].lower()
        fleet_name = f"fleet-{fleet_uuid}-1"
        
        if gpu_enabled:
            image = DOCLING_GPU_IMAGE
            cmd = [
                'ibmcloud', 'code-engine', 'fleet', 'create',
                '--name', fleet_name,
                '--tasks-state-store', CE_FLEET_TASK_STORE,
                '--subnetpool-name', CE_FLEET_SUBNETPOOL,
                '--image', image,
                '--registry-secret', CE_REGISTRY_SECRET,
                '--max-scale', '1',
                '--tasks-from-local-file', commands_jsonl_path,
                '--gpu', 'l40s:1',
                '--mount-data-store', f'/input={CE_INPUT_STORE}:/docling',
                '--mount-data-store', f'/output={CE_OUTPUT_STORE}:/docling'
            ]
        else:
            image = DOCLING_CPU_IMAGE
            cmd = [
                'ibmcloud', 'code-engine', 'fleet', 'create',
                '--name', fleet_name,
                '--tasks-state-store', CE_FLEET_TASK_STORE,
                '--subnetpool-name', CE_FLEET_SUBNETPOOL,
                '--image', image,
                '--registry-secret', CE_REGISTRY_SECRET,
                '--worker-profile', 'mx3d-24x240',
                '--max-scale', str(max_scale),
                '--tasks-from-local-file', commands_jsonl_path,
                '--cpu', '12',
                '--memory', '120G',
                '--mount-data-store', f'/input={CE_INPUT_STORE}:/docling',
                '--mount-data-store', f'/output={CE_OUTPUT_STORE}:/docling'
            ]
        
        log_msg = f"Launching fleet: {fleet_name} ({'GPU' if gpu_enabled else 'CPU'})"
        logger.info(log_msg)
        update_job(job_id, 
                  status='fleet_launching',
                  fleet_id=fleet_name,
                  log=jobs[job_id]['log'] + [log_msg, f"Command: {' '.join(cmd)}"])
        
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
        
        if result.returncode == 0:
            success_msg = f"Fleet launched successfully: {fleet_name}"
            logger.info(success_msg)
            update_job(job_id, 
                      status='fleet_running',
                      log=jobs[job_id]['log'] + [success_msg, result.stdout])
            return fleet_name
        else:
            error_msg = f"Fleet launch failed: {result.stderr}"
            logger.error(error_msg)
            update_job(job_id, 
                      status='failed',
                      errors=[error_msg],
                      log=jobs[job_id]['log'] + [error_msg])
            return None
            
    except subprocess.TimeoutExpired:
        error_msg = "Fleet launch timed out"
        update_job(job_id, status='failed', errors=[error_msg])
        return None
    except Exception as e:
        error_msg = f"Fleet launch error: {str(e)}"
        update_job(job_id, status='failed', errors=[error_msg])
        return None


def process_fleet(job_id, input_files, output_dir, gpu_enabled=False):
    """Process documents using Code Engine serverless fleet."""
    try:
        update_job(job_id, status='preparing', log=[f"Preparing fleet processing ({'GPU' if gpu_enabled else 'CPU'})..."])
        
        # Generate commands.jsonl
        commands_content = generate_commands_jsonl(input_files, output_dir)
        commands_file = Path(UPLOAD_FOLDER) / f"commands_{job_id}.jsonl"
        
        with open(commands_file, 'w') as f:
            f.write(commands_content)
        
        log_msg = f"Generated {len(input_files)} tasks in {commands_file}"
        update_job(job_id, log=jobs[job_id]['log'] + [log_msg])
        
        # Launch fleet
        fleet_id = launch_fleet(job_id, str(commands_file), gpu_enabled=gpu_enabled)
        
        if fleet_id:
            update_job(job_id, 
                      fleet_id=fleet_id,
                      log=jobs[job_id]['log'] + [f"Fleet {fleet_id} is processing documents..."])
        
    except Exception as e:
        error_msg = f"Fleet processing error: {str(e)}"
        logger.error(error_msg)
        update_job(job_id, status='failed', errors=[error_msg])


# ============================================================
# Routes
# ============================================================

@app.route('/')
def index():
    """Main page."""
    return render_template('index.html',
                          processing_mode=PROCESSING_MODE,
                          ce_region=CE_REGION)


@app.route('/upload', methods=['POST'])
def upload_files():
    """Handle file upload and start processing."""
    try:
        if 'files' not in request.files and 'folder_path' not in request.form:
            return jsonify({'error': 'No files or folder path provided'}), 400
        
        job_id = str(uuid.uuid4())
        input_files = []
        timestamp = get_timestamp()
        
        # Handle file uploads — accept all files, Docling detects format automatically
        if 'files' in request.files:
            files = request.files.getlist('files')
            upload_dir = Path(UPLOAD_FOLDER) / job_id
            upload_dir.mkdir(parents=True, exist_ok=True)

            for file in files:
                if file and file.filename:
                    filename = secure_filename(file.filename)
                    file_path = upload_dir / filename
                    file.save(str(file_path))
                    input_files.append(str(file_path))
        
        # Handle folder path — collect all files, Docling detects format automatically
        if 'folder_path' in request.form and request.form['folder_path']:
            folder_path = Path(request.form['folder_path'])
            if folder_path.exists() and folder_path.is_dir():
                for p in sorted(folder_path.rglob('*')):
                    if p.is_file():
                        input_files.append(str(p))
            else:
                return jsonify({'error': f'Folder not found: {folder_path}'}), 400
        
        if not input_files:
            return jsonify({'error': 'No valid files found to process'}), 400
        
        # Determine output destination
        output_dest = request.form.get('output_dest', OUTPUT_FOLDER)
        processing_mode = request.form.get('processing_mode', PROCESSING_MODE)
        gpu_enabled = request.form.get('gpu_enabled', 'false').lower() == 'true'
        
        # Create output directory
        if processing_mode == 'local':
            output_dir = Path(LOCAL_OUTPUT_FOLDER) / timestamp
        else:
            output_dir = Path(output_dest) if output_dest else Path(OUTPUT_FOLDER) / timestamp
        output_dir.mkdir(parents=True, exist_ok=True)
        
        # Create job
        job = create_job(job_id, input_files, str(output_dir), processing_mode, gpu_enabled)
        
        # Start processing in background thread
        if processing_mode == 'local':
            thread = threading.Thread(
                target=process_local,
                args=(job_id, input_files, str(output_dir))
            )
        elif processing_mode in ('fleet-cpu', 'fleet-gpu'):
            thread = threading.Thread(
                target=process_fleet,
                args=(job_id, input_files, str(output_dir), gpu_enabled or processing_mode == 'fleet-gpu')
            )
        else:
            return jsonify({'error': f'Unknown processing mode: {processing_mode}'}), 400
        
        thread.daemon = True
        thread.start()
        
        logger.info(f"Job {job_id} started: {len(input_files)} files, mode={processing_mode}, gpu={gpu_enabled}")
        
        return jsonify({
            'job_id': job_id,
            'status': 'pending',
            'total_files': len(input_files),
            'processing_mode': processing_mode,
            'gpu_enabled': gpu_enabled,
            'output_dir': str(output_dir)
        })
        
    except Exception as e:
        logger.error(f"Upload error: {str(e)}")
        return jsonify({'error': str(e)}), 500


@app.route('/job/<job_id>')
def get_job(job_id):
    """Get job status."""
    if job_id not in jobs:
        return jsonify({'error': 'Job not found'}), 404
    return jsonify(jobs[job_id])


@app.route('/jobs')
def list_jobs():
    """List all jobs."""
    return jsonify(list(jobs.values()))


@app.route('/job/<job_id>/download')
def download_results(job_id):
    """Download job results as a zip file."""
    import zipfile
    import io
    
    if job_id not in jobs:
        return jsonify({'error': 'Job not found'}), 404
    
    job = jobs[job_id]
    if job['status'] not in ('completed', 'completed_with_errors'):
        return jsonify({'error': 'Job not yet completed'}), 400
    
    # Create zip in memory
    zip_buffer = io.BytesIO()
    with zipfile.ZipFile(zip_buffer, 'w', zipfile.ZIP_DEFLATED) as zip_file:
        for result in job['results']:
            if result.get('status') == 'success' and Path(result['output']).exists():
                zip_file.write(result['output'], Path(result['output']).name)
    
    zip_buffer.seek(0)
    timestamp = get_timestamp()
    
    return send_file(
        zip_buffer,
        mimetype='application/zip',
        as_attachment=True,
        download_name=f'docling_results_{timestamp}.zip'
    )


@app.route('/job/<job_id>/result/<filename>')
def download_single_result(job_id, filename):
    """Download a single result file."""
    if job_id not in jobs:
        return jsonify({'error': 'Job not found'}), 404
    
    job = jobs[job_id]
    for result in job['results']:
        if Path(result.get('output', '')).name == filename:
            if Path(result['output']).exists():
                return send_file(result['output'], as_attachment=True)
    
    return jsonify({'error': 'File not found'}), 404


@app.route('/local/process', methods=['POST'])
def process_local_folder():
    """Process documents from the local input folder."""
    try:
        input_dir = Path(LOCAL_INPUT_FOLDER)
        if not input_dir.exists():
            return jsonify({'error': f'Input folder not found: {LOCAL_INPUT_FOLDER}'}), 400
        
        # Collect all files — Docling auto-detects format, no extension filtering needed
        input_files = [str(p) for p in sorted(input_dir.rglob('*')) if p.is_file()]
        
        if not input_files:
            return jsonify({'error': f'No supported files found in {LOCAL_INPUT_FOLDER}'}), 400
        
        job_id = str(uuid.uuid4())
        timestamp = get_timestamp()
        output_dir = Path(LOCAL_OUTPUT_FOLDER) / timestamp
        output_dir.mkdir(parents=True, exist_ok=True)
        
        gpu_enabled = request.json.get('gpu_enabled', False) if request.is_json else False
        processing_mode = request.json.get('processing_mode', 'local') if request.is_json else 'local'
        
        job = create_job(job_id, input_files, str(output_dir), processing_mode, gpu_enabled)
        
        thread = threading.Thread(
            target=process_local,
            args=(job_id, input_files, str(output_dir))
        )
        thread.daemon = True
        thread.start()
        
        return jsonify({
            'job_id': job_id,
            'status': 'pending',
            'total_files': len(input_files),
            'input_dir': str(input_dir),
            'output_dir': str(output_dir)
        })
        
    except Exception as e:
        logger.error(f"Local process error: {str(e)}")
        return jsonify({'error': str(e)}), 500


@app.route('/fleet/status/<fleet_id>')
def fleet_status(fleet_id):
    """Get fleet status from IBM Cloud Code Engine."""
    try:
        result = subprocess.run(
            ['ibmcloud', 'ce', 'fleet', 'get', '--id', fleet_id, '--output', 'json'],
            capture_output=True, text=True, timeout=30
        )
        if result.returncode == 0:
            return jsonify(json.loads(result.stdout))
        else:
            return jsonify({'error': result.stderr}), 400
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/health')
def health():
    """Health check endpoint."""
    return jsonify({
        'status': 'healthy',
        'timestamp': datetime.utcnow().isoformat(),
        'processing_mode': PROCESSING_MODE,
        'version': '1.0.0'
    })


@app.route('/config')
def get_config():
    """Get application configuration (non-sensitive)."""
    return jsonify({
        'processing_mode': PROCESSING_MODE,
        'ce_region': CE_REGION,
        'allowed_formats': ['pdf', 'docx', 'pptx', 'xlsx', 'html', 'md', 'asciidoc', 'csv', 'png', 'jpg', 'jpeg', 'tiff', 'bmp', 'webp'],
        'max_file_size_mb': MAX_CONTENT_LENGTH // (1024 * 1024),
        'docling_gpu_image': DOCLING_GPU_IMAGE,
        'docling_cpu_image': DOCLING_CPU_IMAGE,
        'local_input_folder': LOCAL_INPUT_FOLDER,
        'local_output_folder': LOCAL_OUTPUT_FOLDER
    })


if __name__ == '__main__':
    port = int(os.getenv('PORT', 8080))
    debug = os.getenv('DEBUG', 'false').lower() == 'true'
    logger.info(f"Starting DoclingGPU app on port {port}, mode={PROCESSING_MODE}")
    app.run(host='0.0.0.0', port=port, debug=debug)

# Made with Bob
