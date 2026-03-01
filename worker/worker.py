"""
DoclingGPU Worker
Standalone document processing worker for IBM Code Engine Serverless Fleet.
Reads documents from /input, converts to Markdown, writes to /output.
Supports both CPU and GPU (CUDA) processing via Docling.
"""

import os
import sys
import json
import time
import logging
import argparse
from pathlib import Path
from datetime import datetime

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger(__name__)

# Code Engine task metadata
TASK_INDEX = os.getenv('CE_TASK_INDEX', '0')
TASK_ID = os.getenv('CE_TASK_ID', 'local')

# Processing configuration
INPUT_DIR = os.getenv('INPUT_DIR', '/input')
OUTPUT_DIR = os.getenv('OUTPUT_DIR', '/output')
NUM_THREADS = int(os.getenv('DOCLING_NUM_THREADS', '4'))
DEVICE = os.getenv('DOCLING_DEVICE', 'auto')  # 'auto', 'cuda', 'cpu', 'mps'
ENABLE_OCR = os.getenv('DOCLING_ENABLE_OCR', 'true').lower() == 'true'
ENABLE_TABLE_STRUCTURE = os.getenv('DOCLING_ENABLE_TABLE_STRUCTURE', 'true').lower() == 'true'
ENABLE_PICTURE_CLASSIFICATION = os.getenv('DOCLING_ENABLE_PICTURE_CLASSIFICATION', 'false').lower() == 'true'


def detect_device():
    """Auto-detect best available device."""
    if DEVICE != 'auto':
        return DEVICE
    try:
        import torch
        if torch.cuda.is_available():
            gpu_name = torch.cuda.get_device_name(0)
            gpu_mem = torch.cuda.get_device_properties(0).total_memory / (1024**3)
            logger.info(f"GPU detected: {gpu_name} ({gpu_mem:.1f} GB VRAM)")
            return 'cuda'
        elif hasattr(torch.backends, 'mps') and torch.backends.mps.is_available():
            logger.info("Apple MPS detected")
            return 'mps'
    except ImportError:
        pass
    logger.info("Using CPU for processing")
    return 'cpu'


def build_converter(device: str):
    """Build and configure the Docling DocumentConverter for all supported formats."""
    from docling.document_converter import DocumentConverter, PdfFormatOption
    from docling.datamodel.base_models import InputFormat
    from docling.datamodel.pipeline_options import (
        PdfPipelineOptions,
        EasyOcrOptions,
    )

    logger.info(f"Building Docling converter (device={device}, ocr={ENABLE_OCR}, tables={ENABLE_TABLE_STRUCTURE})")

    pipeline_options = PdfPipelineOptions()
    pipeline_options.do_ocr = ENABLE_OCR
    pipeline_options.do_table_structure = ENABLE_TABLE_STRUCTURE

    if ENABLE_OCR:
        # Use EasyOCR which supports GPU acceleration
        ocr_options = EasyOcrOptions(
            force_full_page_ocr=False,
            use_gpu=(device == 'cuda')
        )
        pipeline_options.ocr_options = ocr_options

    if ENABLE_PICTURE_CLASSIFICATION:
        pipeline_options.generate_picture_images = True
        pipeline_options.images_scale = 2.0

    # Set accelerator device
    try:
        from docling.datamodel.accelerator_options import AcceleratorDevice, AcceleratorOptions
        device_map = {
            'cuda': AcceleratorDevice.CUDA,
            'mps': AcceleratorDevice.MPS,
            'cpu': AcceleratorDevice.CPU,
        }
        if device in device_map:
            pipeline_options.accelerator_options = AcceleratorOptions(
                num_threads=NUM_THREADS,
                device=device_map[device]
            )
    except ImportError:
        logger.warning("AcceleratorOptions not available in this Docling version")

    # Accept ALL Docling-supported formats — format is auto-detected per file
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

    return converter


def process_file(converter, input_path: Path, output_dir: Path) -> dict:
    """Process a single document file."""
    start_time = time.perf_counter()
    output_file = output_dir / f"docling_{input_path.name}.md"

    try:
        logger.info(f"Processing: {input_path.name}")
        result = converter.convert(str(input_path))
        markdown_content = result.document.export_to_markdown()
        elapsed = time.perf_counter() - start_time

        # Write output with YAML frontmatter metadata
        with open(output_file, 'w', encoding='utf-8') as f:
            f.write("---\n")
            f.write(f"source: {input_path.name}\n")
            f.write(f"source_path: {input_path}\n")
            f.write(f"processed_at: {datetime.utcnow().isoformat()}Z\n")
            f.write(f"processing_time_seconds: {elapsed:.3f}\n")
            f.write(f"device: {DEVICE}\n")
            f.write(f"task_index: {TASK_INDEX}\n")
            f.write(f"task_id: {TASK_ID}\n")
            f.write(f"pages: {len(result.document.pages) if hasattr(result.document, 'pages') else 'unknown'}\n")
            f.write("---\n\n")
            f.write(markdown_content)

        logger.info(f"✓ {input_path.name} → {output_file.name} ({elapsed:.2f}s)")

        return {
            'input': str(input_path),
            'output': str(output_file),
            'status': 'success',
            'processing_time': elapsed,
            'output_size_bytes': output_file.stat().st_size
        }

    except Exception as e:
        elapsed = time.perf_counter() - start_time
        logger.error(f"✗ Failed to process {input_path.name}: {e}")
        return {
            'input': str(input_path),
            'output': None,
            'status': 'failed',
            'error': str(e),
            'processing_time': elapsed
        }


def process_batch(input_files: list, output_dir: Path, device: str) -> dict:
    """Process a batch of documents."""
    total_start = time.perf_counter()
    results = []
    errors = []

    logger.info(f"=== DoclingGPU Worker ===")
    logger.info(f"Task Index: {TASK_INDEX}")
    logger.info(f"Device: {device}")
    logger.info(f"Files to process: {len(input_files)}")
    logger.info(f"Output directory: {output_dir}")
    logger.info("=" * 40)

    # Build converter once (expensive operation)
    converter = build_converter(device)
    logger.info("Converter initialized, starting batch processing...")

    for i, input_path in enumerate(input_files):
        logger.info(f"[{i+1}/{len(input_files)}] {input_path.name}")
        result = process_file(converter, input_path, output_dir)
        results.append(result)
        if result['status'] == 'failed':
            errors.append(result)

    total_elapsed = time.perf_counter() - total_start
    successful = len([r for r in results if r['status'] == 'success'])

    summary = {
        'task_index': TASK_INDEX,
        'task_id': TASK_ID,
        'device': device,
        'total_files': len(input_files),
        'successful': successful,
        'failed': len(errors),
        'total_processing_time': total_elapsed,
        'avg_time_per_file': total_elapsed / len(input_files) if input_files else 0,
        'results': results
    }

    logger.info("=" * 40)
    logger.info(f"Batch complete: {successful}/{len(input_files)} files processed in {total_elapsed:.2f}s")
    if errors:
        logger.warning(f"Errors: {len(errors)} files failed")

    return summary


def find_input_files(input_dir: Path) -> list:
    """Find all files in the input directory. Docling auto-detects supported formats."""
    # Collect every file recursively — Docling will skip unsupported formats gracefully
    return sorted([p for p in input_dir.rglob('*') if p.is_file()])


def main():
    parser = argparse.ArgumentParser(
        description='DoclingGPU Worker - Process documents with Docling on IBM Code Engine'
    )
    parser.add_argument(
        '--input', '-i',
        default=INPUT_DIR,
        help=f'Input directory or file (default: {INPUT_DIR})'
    )
    parser.add_argument(
        '--output', '-o',
        default=OUTPUT_DIR,
        help=f'Output directory (default: {OUTPUT_DIR})'
    )
    parser.add_argument(
        '--file-list', '-f',
        help='Path to a text file containing list of files to process (one per line)'
    )
    parser.add_argument(
        '--device',
        default=DEVICE,
        choices=['auto', 'cuda', 'cpu', 'mps'],
        help='Processing device (default: auto)'
    )
    parser.add_argument(
        '--threads',
        type=int,
        default=NUM_THREADS,
        help=f'Number of threads (default: {NUM_THREADS})'
    )
    parser.add_argument(
        '--no-ocr',
        action='store_true',
        help='Disable OCR processing'
    )
    parser.add_argument(
        '--no-tables',
        action='store_true',
        help='Disable table structure detection'
    )
    parser.add_argument(
        '--summary-file',
        help='Write processing summary JSON to this file'
    )

    args = parser.parse_args()

    # Override globals from args
    global DEVICE, NUM_THREADS, ENABLE_OCR, ENABLE_TABLE_STRUCTURE
    DEVICE = args.device
    NUM_THREADS = args.threads
    if args.no_ocr:
        ENABLE_OCR = False
    if args.no_tables:
        ENABLE_TABLE_STRUCTURE = False

    # Detect device
    device = detect_device()

    # Determine input files
    input_files = []

    if args.file_list:
        # Read file list from text file
        file_list_path = Path(args.file_list)
        if not file_list_path.exists():
            logger.error(f"File list not found: {args.file_list}")
            sys.exit(1)
        with open(file_list_path) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#'):
                    p = Path(line)
                    if p.exists():
                        input_files.append(p)
                    else:
                        logger.warning(f"File not found: {line}")
    else:
        input_path = Path(args.input)
        if input_path.is_file():
            input_files = [input_path]
        elif input_path.is_dir():
            input_files = find_input_files(input_path)
        else:
            logger.error(f"Input not found: {args.input}")
            sys.exit(1)

    if not input_files:
        logger.warning("No input files found. Exiting.")
        sys.exit(0)

    # Ensure output directory exists
    output_dir = Path(args.output)
    output_dir.mkdir(parents=True, exist_ok=True)

    # Process batch
    summary = process_batch(input_files, output_dir, device)

    # Write summary
    if args.summary_file:
        summary_path = Path(args.summary_file)
        with open(summary_path, 'w') as f:
            json.dump(summary, f, indent=2)
        logger.info(f"Summary written to {summary_path}")

    # Also write summary to output dir
    summary_output = output_dir / f"processing_summary_task{TASK_INDEX}.json"
    with open(summary_output, 'w') as f:
        json.dump(summary, f, indent=2)

    # Exit with error code if any failures
    if summary['failed'] > 0:
        logger.warning(f"Completed with {summary['failed']} failures")
        sys.exit(1)

    logger.info("All files processed successfully")
    sys.exit(0)


if __name__ == '__main__':
    main()

# Made with Bob
