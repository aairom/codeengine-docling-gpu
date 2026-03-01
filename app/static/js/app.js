/**
 * DoclingGPU - Frontend Application
 * IBM Code Engine Serverless Document Processing
 */

'use strict';

// ============================================================
// State
// ============================================================
const state = {
  selectedFiles: [],
  activeJobs: {},
  pollIntervals: {},
};

// ============================================================
// File Handling
// ============================================================

const dropZone = document.getElementById('dropZone');
const fileInput = document.getElementById('fileInput');
const fileList = document.getElementById('fileList');
const fileItems = document.getElementById('fileItems');
const fileCount = document.getElementById('fileCount');

// Drag & Drop
dropZone.addEventListener('dragover', (e) => {
  e.preventDefault();
  dropZone.classList.add('drag-over');
});

dropZone.addEventListener('dragleave', () => {
  dropZone.classList.remove('drag-over');
});

dropZone.addEventListener('drop', (e) => {
  e.preventDefault();
  dropZone.classList.remove('drag-over');
  const files = Array.from(e.dataTransfer.files);
  addFiles(files);
});

dropZone.addEventListener('click', () => fileInput.click());

fileInput.addEventListener('change', (e) => {
  const files = Array.from(e.target.files);
  addFiles(files);
});

function addFiles(files) {
  const allowed = ['pdf', 'docx', 'pptx', 'xlsx', 'html', 'md', 'txt', 'png', 'jpg', 'jpeg', 'tiff'];
  const validFiles = files.filter(f => {
    const ext = f.name.split('.').pop().toLowerCase();
    return allowed.includes(ext);
  });

  if (validFiles.length < files.length) {
    showNotification(`${files.length - validFiles.length} file(s) skipped (unsupported format)`, 'warning');
  }

  state.selectedFiles = [...state.selectedFiles, ...validFiles];
  renderFileList();
}

function renderFileList() {
  if (state.selectedFiles.length === 0) {
    fileList.style.display = 'none';
    return;
  }

  fileList.style.display = 'block';
  fileCount.textContent = `${state.selectedFiles.length} file${state.selectedFiles.length !== 1 ? 's' : ''} selected`;

  fileItems.innerHTML = state.selectedFiles.map((file, i) => {
    const ext = file.name.split('.').pop().toLowerCase();
    const icon = getFileIcon(ext);
    const size = formatFileSize(file.size);
    return `
      <li>
        <span class="file-icon">${icon}</span>
        <span class="file-name" title="${file.name}">${file.name}</span>
        <span class="file-size">${size}</span>
        <button class="btn btn--ghost btn--sm" onclick="removeFile(${i})" style="padding:2px 6px;font-size:11px;">✕</button>
      </li>
    `;
  }).join('');
}

function removeFile(index) {
  state.selectedFiles.splice(index, 1);
  renderFileList();
}

function clearFiles() {
  state.selectedFiles = [];
  fileInput.value = '';
  renderFileList();
}

function getFileIcon(ext) {
  const icons = {
    pdf: '📄', docx: '📝', pptx: '📊', xlsx: '📈',
    html: '🌐', md: '📋', txt: '📃',
    png: '🖼️', jpg: '🖼️', jpeg: '🖼️', tiff: '🖼️'
  };
  return icons[ext] || '📁';
}

function formatFileSize(bytes) {
  if (bytes < 1024) return bytes + ' B';
  if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + ' KB';
  return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
}

// ============================================================
// Processing Mode Toggle
// ============================================================

document.querySelectorAll('input[name="processingMode"]').forEach(radio => {
  radio.addEventListener('change', (e) => {
    const gpuOptions = document.getElementById('gpuOptions');
    gpuOptions.style.display = e.target.value === 'fleet-gpu' ? 'block' : 'none';
  });
});

// ============================================================
// Start Processing
// ============================================================

async function startProcessing() {
  const folderPath = document.getElementById('folderPath').value.trim();
  const outputDest = document.getElementById('outputDest').value.trim();
  const processingMode = document.querySelector('input[name="processingMode"]:checked').value;
  const gpuEnabled = processingMode === 'fleet-gpu';

  if (state.selectedFiles.length === 0 && !folderPath) {
    showNotification('Please select files or enter a folder path', 'error');
    return;
  }

  const btn = document.getElementById('processBtn');
  btn.disabled = true;
  btn.innerHTML = '<span class="spinner"></span> Starting...';

  try {
    const formData = new FormData();

    // Append files
    state.selectedFiles.forEach(file => {
      formData.append('files', file);
    });

    if (folderPath) formData.append('folder_path', folderPath);
    if (outputDest) formData.append('output_dest', outputDest);
    formData.append('processing_mode', processingMode);
    formData.append('gpu_enabled', gpuEnabled.toString());

    const response = await fetch('/upload', {
      method: 'POST',
      body: formData
    });

    const data = await response.json();

    if (!response.ok) {
      throw new Error(data.error || 'Upload failed');
    }

    showNotification(`Job started: ${data.job_id.substring(0, 8)}... (${data.total_files} files)`, 'success');

    // Clear files after successful upload
    clearFiles();
    document.getElementById('folderPath').value = '';

    // Start monitoring the job
    addJobToUI(data);
    startPolling(data.job_id);

    // Scroll to jobs section
    document.getElementById('jobs').scrollIntoView({ behavior: 'smooth' });

  } catch (err) {
    showNotification(`Error: ${err.message}`, 'error');
  } finally {
    btn.disabled = false;
    btn.innerHTML = '<span class="btn-icon">▶</span> Start Processing';
  }
}

async function processLocalFolder() {
  const btn = event.target;
  btn.disabled = true;
  btn.textContent = 'Starting...';

  try {
    const response = await fetch('/local/process', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ processing_mode: 'local' })
    });

    const data = await response.json();

    if (!response.ok) {
      throw new Error(data.error || 'Failed to start processing');
    }

    showNotification(`Processing ${data.total_files} files from ./input`, 'success');
    addJobToUI(data);
    startPolling(data.job_id);
    document.getElementById('jobs').scrollIntoView({ behavior: 'smooth' });

  } catch (err) {
    showNotification(`Error: ${err.message}`, 'error');
  } finally {
    btn.disabled = false;
    btn.textContent = 'Process ./input Folder';
  }
}

// ============================================================
// Job Management
// ============================================================

function addJobToUI(jobData) {
  state.activeJobs[jobData.job_id] = jobData;
  renderJobs();
}

function renderJobs() {
  const container = document.getElementById('jobsContainer');
  const emptyState = document.getElementById('emptyJobs');
  const allJobs = Object.values(state.activeJobs);

  if (allJobs.length === 0) {
    emptyState.style.display = 'block';
    return;
  }

  emptyState.style.display = 'none';

  // Sort by created_at descending
  allJobs.sort((a, b) => new Date(b.created_at || 0) - new Date(a.created_at || 0));

  container.innerHTML = allJobs.map(job => renderJobCard(job)).join('');
}

function renderJobCard(job) {
  const statusClass = `status-badge--${job.status}`;
  const statusLabel = formatStatus(job.status);
  const progressClass = job.status === 'completed' ? 'progress-fill--completed' :
                        job.status === 'failed' ? 'progress-fill--failed' : '';
  const progress = job.progress || 0;
  const isActive = ['pending', 'running', 'preparing', 'fleet_launching', 'fleet_running'].includes(job.status);
  const isCompleted = ['completed', 'completed_with_errors'].includes(job.status);

  const modeIcon = job.processing_mode === 'fleet-gpu' ? '🔥' :
                   job.processing_mode === 'fleet-cpu' ? '☁️' : '🖥️';

  const logHtml = job.log && job.log.length > 0 ? `
    <div class="job-log" id="log-${job.id}">
      ${job.log.map(line => {
        const cls = line.startsWith('✓') ? 'log-line--success' :
                    line.startsWith('✗') ? 'log-line--error' :
                    line.startsWith('Fleet') || line.startsWith('Launching') ? 'log-line--info' : '';
        return `<div class="${cls}">${escapeHtml(line)}</div>`;
      }).join('')}
    </div>
  ` : '';

  return `
    <div class="job-card" id="job-${job.id}">
      <div class="job-header">
        <div>
          <div class="job-id">${job.id}</div>
          <div class="job-meta">
            <span>${modeIcon} ${job.processing_mode || 'local'}</span>
            <span>📄 ${job.total_files || 0} files</span>
            <span>✅ ${job.processed_files || 0} done</span>
            ${job.fleet_id ? `<span>🚀 Fleet: ${job.fleet_id}</span>` : ''}
            ${job.created_at ? `<span>🕐 ${formatTime(job.created_at)}</span>` : ''}
          </div>
        </div>
        <span class="status-badge ${statusClass} ${isActive ? 'pulse' : ''}">
          ${isActive ? '<span class="spinner" style="width:10px;height:10px;border-width:1.5px;"></span> ' : ''}
          ${statusLabel}
        </span>
      </div>

      <div class="progress-bar">
        <div class="progress-fill ${progressClass}" style="width: ${progress}%"></div>
      </div>

      <div class="job-actions">
        ${isCompleted ? `
          <button class="btn btn--primary btn--sm" onclick="downloadResults('${job.id}')">
            ⬇ Download Results
          </button>
        ` : ''}
        <button class="btn btn--ghost btn--sm" onclick="showJobDetails('${job.id}')">
          📋 Details
        </button>
        ${isActive ? `
          <button class="btn btn--ghost btn--sm" onclick="refreshJob('${job.id}')">
            ↻ Refresh
          </button>
        ` : ''}
        ${job.errors && job.errors.length > 0 ? `
          <span style="font-size:12px;color:#da1e28;">⚠ ${job.errors.length} error(s)</span>
        ` : ''}
      </div>

      ${logHtml}
    </div>
  `;
}

function formatStatus(status) {
  const labels = {
    pending: 'Pending',
    running: 'Running',
    preparing: 'Preparing',
    fleet_launching: 'Launching Fleet',
    fleet_running: 'Fleet Running',
    completed: 'Completed',
    completed_with_errors: 'Completed (errors)',
    failed: 'Failed'
  };
  return labels[status] || status;
}

function formatTime(isoString) {
  try {
    const d = new Date(isoString);
    return d.toLocaleTimeString();
  } catch { return isoString; }
}

function escapeHtml(str) {
  return str.replace(/&/g, '&').replace(/</g, '<').replace(/>/g, '>');
}

// ============================================================
// Polling
// ============================================================

function startPolling(jobId) {
  if (state.pollIntervals[jobId]) return;

  state.pollIntervals[jobId] = setInterval(async () => {
    await refreshJob(jobId);
  }, 2000);
}

function stopPolling(jobId) {
  if (state.pollIntervals[jobId]) {
    clearInterval(state.pollIntervals[jobId]);
    delete state.pollIntervals[jobId];
  }
}

async function refreshJob(jobId) {
  try {
    const response = await fetch(`/job/${jobId}`);
    if (!response.ok) return;

    const job = await response.json();
    state.activeJobs[jobId] = job;

    // Update the job card in place
    const card = document.getElementById(`job-${jobId}`);
    if (card) {
      card.outerHTML = renderJobCard(job);
    } else {
      renderJobs();
    }

    // Stop polling when done
    const terminalStates = ['completed', 'completed_with_errors', 'failed'];
    if (terminalStates.includes(job.status)) {
      stopPolling(jobId);
    }

  } catch (err) {
    console.error('Poll error:', err);
  }
}

async function refreshJobs() {
  try {
    const response = await fetch('/jobs');
    const jobs = await response.json();
    jobs.forEach(job => {
      state.activeJobs[job.id] = job;
    });
    renderJobs();
  } catch (err) {
    console.error('Refresh error:', err);
  }
}

// ============================================================
// Download
// ============================================================

function downloadResults(jobId) {
  window.location.href = `/job/${jobId}/download`;
}

// ============================================================
// Job Details Modal
// ============================================================

function showJobDetails(jobId) {
  const job = state.activeJobs[jobId];
  if (!job) return;

  const modal = document.getElementById('jobModal');
  const modalTitle = document.getElementById('modalTitle');
  const modalBody = document.getElementById('modalBody');

  modalTitle.textContent = `Job Details: ${jobId.substring(0, 8)}...`;

  const resultsHtml = job.results && job.results.length > 0 ? `
    <div style="margin-top:16px;">
      <strong style="font-size:13px;">Results (${job.results.length} files):</strong>
      <ul style="list-style:none;margin-top:8px;">
        ${job.results.map(r => `
          <li style="display:flex;align-items:center;gap:8px;padding:6px 0;border-bottom:1px solid #e0e0e0;font-size:13px;">
            <span>${r.status === 'success' ? '✅' : '❌'}</span>
            <span style="flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;" title="${r.output || ''}">
              ${r.output ? r.output.split('/').pop() : 'unknown'}
            </span>
            ${r.processing_time ? `<span style="font-family:monospace;font-size:11px;color:#8d8d8d;">${r.processing_time.toFixed(2)}s</span>` : ''}
            ${r.status === 'success' && r.output ? `
              <a href="/job/${jobId}/result/${encodeURIComponent(r.output.split('/').pop())}" 
                 class="btn btn--ghost btn--sm" style="padding:2px 8px;font-size:11px;">⬇</a>
            ` : ''}
          </li>
        `).join('')}
      </ul>
    </div>
  ` : '';

  const errorsHtml = job.errors && job.errors.length > 0 ? `
    <div style="margin-top:16px;background:#fff1f1;border-radius:6px;padding:12px;">
      <strong style="font-size:13px;color:#da1e28;">Errors:</strong>
      <ul style="list-style:none;margin-top:8px;">
        ${job.errors.map(e => `<li style="font-size:12px;color:#da1e28;margin-bottom:4px;">• ${escapeHtml(e)}</li>`).join('')}
      </ul>
    </div>
  ` : '';

  modalBody.innerHTML = `
    <div style="display:grid;grid-template-columns:1fr 1fr;gap:12px;margin-bottom:16px;">
      <div>
        <div style="font-size:11px;color:#8d8d8d;text-transform:uppercase;letter-spacing:0.06em;margin-bottom:4px;">Status</div>
        <span class="status-badge status-badge--${job.status}">${formatStatus(job.status)}</span>
      </div>
      <div>
        <div style="font-size:11px;color:#8d8d8d;text-transform:uppercase;letter-spacing:0.06em;margin-bottom:4px;">Mode</div>
        <span style="font-size:14px;font-weight:600;">${job.processing_mode || 'local'}</span>
      </div>
      <div>
        <div style="font-size:11px;color:#8d8d8d;text-transform:uppercase;letter-spacing:0.06em;margin-bottom:4px;">Progress</div>
        <span style="font-size:14px;font-weight:600;">${job.progress || 0}% (${job.processed_files || 0}/${job.total_files || 0})</span>
      </div>
      <div>
        <div style="font-size:11px;color:#8d8d8d;text-transform:uppercase;letter-spacing:0.06em;margin-bottom:4px;">Output</div>
        <span style="font-size:12px;font-family:monospace;word-break:break-all;">${job.output_dest || '-'}</span>
      </div>
      ${job.fleet_id ? `
        <div style="grid-column:1/-1;">
          <div style="font-size:11px;color:#8d8d8d;text-transform:uppercase;letter-spacing:0.06em;margin-bottom:4px;">Fleet ID</div>
          <span style="font-size:12px;font-family:monospace;">${job.fleet_id}</span>
        </div>
      ` : ''}
    </div>

    ${job.log && job.log.length > 0 ? `
      <div>
        <strong style="font-size:13px;">Processing Log:</strong>
        <div class="job-log" style="margin-top:8px;max-height:250px;">
          ${job.log.map(line => {
            const cls = line.startsWith('✓') ? 'log-line--success' :
                        line.startsWith('✗') ? 'log-line--error' :
                        line.startsWith('Fleet') || line.startsWith('Launching') ? 'log-line--info' : '';
            return `<div class="${cls}">${escapeHtml(line)}</div>`;
          }).join('')}
        </div>
      </div>
    ` : ''}

    ${resultsHtml}
    ${errorsHtml}

    <div style="margin-top:20px;display:flex;gap:8px;">
      ${['completed', 'completed_with_errors'].includes(job.status) ? `
        <button class="btn btn--primary btn--sm" onclick="downloadResults('${jobId}');closeModal()">
          ⬇ Download All Results
        </button>
      ` : ''}
      <button class="btn btn--ghost btn--sm" onclick="closeModal()">Close</button>
    </div>
  `;

  modal.style.display = 'flex';
}

function closeModal() {
  document.getElementById('jobModal').style.display = 'none';
}

// Close modal on Escape
document.addEventListener('keydown', (e) => {
  if (e.key === 'Escape') closeModal();
});

// ============================================================
// Notifications
// ============================================================

function showNotification(message, type = 'info') {
  const existing = document.querySelector('.notification');
  if (existing) existing.remove();

  const colors = {
    success: { bg: '#defbe6', border: '#24a148', text: '#065f46' },
    error: { bg: '#fff1f1', border: '#da1e28', text: '#da1e28' },
    warning: { bg: '#fcf4d6', border: '#f1c21b', text: '#92400e' },
    info: { bg: '#edf5ff', border: '#0f62fe', text: '#0043ce' }
  };

  const c = colors[type] || colors.info;
  const icons = { success: '✅', error: '❌', warning: '⚠️', info: 'ℹ️' };

  const notif = document.createElement('div');
  notif.className = 'notification';
  notif.style.cssText = `
    position: fixed;
    top: 72px;
    right: 24px;
    z-index: 9999;
    background: ${c.bg};
    border: 1px solid ${c.border};
    color: ${c.text};
    padding: 12px 20px;
    border-radius: 8px;
    font-size: 14px;
    font-weight: 500;
    box-shadow: 0 4px 12px rgba(0,0,0,0.15);
    display: flex;
    align-items: center;
    gap: 8px;
    max-width: 400px;
    animation: slideIn 0.3s ease;
  `;
  notif.innerHTML = `${icons[type]} ${escapeHtml(message)}`;

  document.body.appendChild(notif);

  setTimeout(() => {
    notif.style.opacity = '0';
    notif.style.transition = 'opacity 0.3s ease';
    setTimeout(() => notif.remove(), 300);
  }, 4000);
}

// Add slideIn animation
const style = document.createElement('style');
style.textContent = `
  @keyframes slideIn {
    from { transform: translateX(100%); opacity: 0; }
    to { transform: translateX(0); opacity: 1; }
  }
`;
document.head.appendChild(style);

// ============================================================
// Init
// ============================================================

document.addEventListener('DOMContentLoaded', () => {
  // Load existing jobs on page load
  refreshJobs();

  // Auto-refresh active jobs
  setInterval(() => {
    Object.keys(state.activeJobs).forEach(jobId => {
      const job = state.activeJobs[jobId];
      const terminalStates = ['completed', 'completed_with_errors', 'failed'];
      if (!terminalStates.includes(job.status) && !state.pollIntervals[jobId]) {
        startPolling(jobId);
      }
    });
  }, 5000);
});

// Made with Bob
