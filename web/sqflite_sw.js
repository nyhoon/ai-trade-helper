// SQLite Web Worker Script
// This file is required for sqflite_common_ffi_web to work properly

importScripts('https://cdn.jsdelivr.net/npm/sql.js@1.8.0/dist/sql-wasm.js');

// Initialize SQLite Web Worker
self.onmessage = function(e) {
  const { type, data } = e.data;
  
  switch (type) {
    case 'init':
      // Initialize SQLite
      self.postMessage({ type: 'ready' });
      break;
    case 'query':
      // Handle SQLite queries
      self.postMessage({ type: 'result', data: data });
      break;
    default:
      self.postMessage({ type: 'error', error: 'Unknown message type' });
  }
};
