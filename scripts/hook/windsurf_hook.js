/**
 * Windsurf Device Identifier Hook Module
 *
 * 🎯 Function: Intercept all device identifier generation at the low level, achieving permanent machine code modification
 *
 * 🔧 Hook Points:
 * 1. child_process.execSync - Intercept REG.exe MachineGuid query
 * 2. crypto.createHash - Intercept SHA256 hash calculation
 * 3. @vscode/deviceid - Intercept devDeviceId retrieval
 * 4. @vscode/windows-registry - Intercept registry read
 * 5. os.networkInterfaces - Intercept MAC address retrieval
 * 6. fs.writeFileSync/writeFile - Intercept storage.json writes, protect telemetry fields
 *
 * 📦 Usage:
 * Inject this code at the top of the main.js file (after Sentry initialization)
 *
 * ⚙️ Configuration:
 * 1. Environment variables: WINDSURF_MACHINE_ID, WINDSURF_MAC_MACHINE_ID, WINDSURF_DEV_DEVICE_ID, WINDSURF_SQM_ID
 * 2. Config file: ~/.windsurf_ids.json
 * 3. Auto-generate: If not configured, auto-generate and persist
 */

// ==================== Configuration Section ====================
// Use var to ensure it works in ES Module environments
var __windsurf_hook_config__ = {
    // Enable Hook (set to false to temporarily disable)
    enabled: true,
    // Output debug logs (set to true for detailed logs)
    debug: false,
    // Config file path (relative to user home directory)
    configFileName: '.windsurf_ids.json',
    // Flag: prevent duplicate injection
    injected: false
};

// ==================== Hook Implementation ====================
// Use IIFE to ensure immediate execution
(function() {
    'use strict';

    // Prevent duplicate injection
    if (globalThis.__windsurf_patched__ || __windsurf_hook_config__.injected) {
        return;
    }
    globalThis.__windsurf_patched__ = true;
    __windsurf_hook_config__.injected = true;

    // Debug log function
    const log = (...args) => {
        if (__windsurf_hook_config__.debug) {
            console.log('[WindsurfHook]', ...args);
        }
    };

    // ==================== ID Generation and Management ====================

    // Generate UUID v4
    const generateUUID = () => {
        return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
            const r = Math.random() * 16 | 0;
            const v = c === 'x' ? r : (r & 0x3 | 0x8);
            return v.toString(16);
        });
    };

    // Generate 64-character hex string (for machineId)
    const generateHex64 = () => {
        let hex = '';
        for (let i = 0; i < 64; i++) {
            hex += Math.floor(Math.random() * 16).toString(16);
        }
        return hex;
    };

    // Generate MAC address format string
    const generateMacAddress = () => {
        const hex = '0123456789ABCDEF';
        let mac = '';
        for (let i = 0; i < 6; i++) {
            if (i > 0) mac += ':';
            mac += hex[Math.floor(Math.random() * 16)];
            mac += hex[Math.floor(Math.random() * 16)];
        }
        return mac;
    };

    // Load or generate ID configuration
    // Note: This Hook is loaded by the script-injected Loader via CommonJS (require).
    // To avoid import.meta and other ESM-only syntax causing Cursor startup parse failures, pure CommonJS syntax is maintained here.
    const loadOrGenerateIds = () => {
        const fs = require('fs');
        const path = require('path');
        const os = require('os');

        const configPath = path.join(os.homedir(), __windsurf_hook_config__.configFileName);

        let ids = null;

        // Try to read from environment variables
        if (process.env.WINDSURF_MACHINE_ID) {
            ids = {
                machineId: process.env.WINDSURF_MACHINE_ID,
                // machineGuid is used to simulate registry MachineGuid/IOPlatformUUID
                machineGuid: process.env.WINDSURF_MACHINE_GUID || generateUUID(),
                macMachineId: process.env.WINDSURF_MAC_MACHINE_ID || generateHex64(),
                devDeviceId: process.env.WINDSURF_DEV_DEVICE_ID || generateUUID(),
                sqmId: process.env.WINDSURF_SQM_ID || `{${generateUUID().toUpperCase()}}`,
                macAddress: process.env.WINDSURF_MAC_ADDRESS || generateMacAddress(),
                sessionId: process.env.WINDSURF_SESSION_ID || generateUUID(),
                firstSessionDate: process.env.WINDSURF_FIRST_SESSION_DATE || new Date().toISOString()
            };
            log('Loaded ID configuration from environment variables');
            return ids;
        }

        // Try to read from configuration file
        try {
            if (fs.existsSync(configPath)) {
                const content = fs.readFileSync(configPath, 'utf8');
                ids = JSON.parse(content);
                // Fill in missing fields for backward compatibility
                let updated = false;
                // 🔧 Fill in core ID fields (used for Hook and storage.json protection)
                if (!ids.machineId || typeof ids.machineId !== 'string') {
                    ids.machineId = generateHex64();
                    updated = true;
                }
                if (!ids.macMachineId || typeof ids.macMachineId !== 'string') {
                    ids.macMachineId = generateHex64();
                    updated = true;
                }
                if (!ids.devDeviceId || typeof ids.devDeviceId !== 'string') {
                    ids.devDeviceId = generateUUID();
                    updated = true;
                }
                if (!ids.sqmId || typeof ids.sqmId !== 'string') {
                    ids.sqmId = `{${generateUUID().toUpperCase()}}`;
                    updated = true;
                }
                if (!ids.machineGuid) {
                    ids.machineGuid = generateUUID();
                    updated = true;
                }
                if (!ids.macAddress) {
                    ids.macAddress = generateMacAddress();
                    updated = true;
                }
                if (!ids.sessionId) {
                    ids.sessionId = generateUUID();
                    updated = true;
                }
                if (!ids.firstSessionDate) {
                    ids.firstSessionDate = new Date().toISOString();
                    updated = true;
                }
                if (updated) {
                    try {
                        fs.writeFileSync(configPath, JSON.stringify(ids, null, 2), 'utf8');
                        log('Filled in and updated ID configuration:', configPath);
                    } catch (e) {
                        log('Failed to fill in configuration file:', e.message);
                    }
                }
                log('Loaded ID configuration from file:', configPath);
                return ids;
            }
        } catch (e) {
            log('Failed to read configuration file:', e.message);
        }

        // Generate new IDs
        ids = {
            machineId: generateHex64(),
            machineGuid: generateUUID(),
            macMachineId: generateHex64(),
            devDeviceId: generateUUID(),
            sqmId: `{${generateUUID().toUpperCase()}}`,
            macAddress: generateMacAddress(),
            sessionId: generateUUID(),
            firstSessionDate: new Date().toISOString(),
            createdAt: new Date().toISOString()
        };

        // Save to configuration file
        try {
            fs.writeFileSync(configPath, JSON.stringify(ids, null, 2), 'utf8');
            log('Generated and saved new ID configuration:', configPath);
        } catch (e) {
            log('Failed to save configuration file:', e.message);
        }

        return ids;
    };

    // Load ID configuration
    const __windsurf_ids__ = loadOrGenerateIds();
    // Unified MachineGuid getter, falls back to first 36 chars of machineId if missing
    const getMachineGuid = () => __windsurf_ids__.machineGuid || __windsurf_ids__.machineId.substring(0, 36);
    log('Current ID configuration:', __windsurf_ids__);
    
    // ==================== Module Hook ====================
    
    const Module = require('module');
    const originalRequire = Module.prototype.require;
    
    // Cache hooked modules
    const hookedModules = new Map();
    
    Module.prototype.require = function(id) {
        // Handle node: prefix
        const normalizedId = (typeof id === 'string' && id.startsWith('node:')) ? id.slice(5) : id;
        const result = originalRequire.apply(this, arguments);
        
        // If already hooked, return cached result
        if (hookedModules.has(normalizedId)) {
            return hookedModules.get(normalizedId);
        }
        
        let hooked = result;
        
        // Hook child_process module
        if (normalizedId === 'child_process') {
            hooked = hookChildProcess(result);
        }
        // Hook os module
        else if (normalizedId === 'os') {
            hooked = hookOs(result);
        }
        // Hook fs module (new: protect storage.json)
        else if (normalizedId === 'fs') {
            hooked = hookFs(result);
        }
        // Hook crypto module
        else if (normalizedId === 'crypto') {
            hooked = hookCrypto(result);
        }
        // Hook @vscode/deviceid module
        else if (normalizedId === '@vscode/deviceid') {
            hooked = hookDeviceId(result);
        }
        // Hook @vscode/windows-registry module
        else if (normalizedId === '@vscode/windows-registry') {
            hooked = hookWindowsRegistry(result);
        }

        // Cache Hook result
        if (hooked !== result) {
            hookedModules.set(normalizedId, hooked);
            log(`Hooked module: ${normalizedId}`);
        }
        
        return hooked;
    };

    // ==================== child_process Hook ====================

    function hookChildProcess(cp) {
        const originalExecSync = cp.execSync;
        const originalExecFileSync = cp.execFileSync;

        cp.execSync = function(command, options) {
            const cmdStr = String(command).toLowerCase();

            // Intercept MachineGuid query
            if (cmdStr.includes('reg') && cmdStr.includes('machineguid')) {
                log('Intercepted MachineGuid query');
                // Return formatted registry output
                return Buffer.from(`\r\n    MachineGuid    REG_SZ    ${getMachineGuid()}\r\n`);
            }

            // Intercept ioreg command (macOS)
            if (cmdStr.includes('ioreg') && cmdStr.includes('ioplatformexpertdevice')) {
                log('Intercepted IOPlatformUUID query');
                return Buffer.from(`"IOPlatformUUID" = "${getMachineGuid().toUpperCase()}"`);
            }

            // Intercept machine-id read (Linux)
            if (cmdStr.includes('machine-id') || cmdStr.includes('hostname')) {
                log('Intercepted machine-id query');
                return Buffer.from(__windsurf_ids__.machineId.substring(0, 32));
            }

            return originalExecSync.apply(this, arguments);
        };

        // Compatible with execFileSync (some versions call the executable directly)
        if (typeof originalExecFileSync === 'function') {
            cp.execFileSync = function(file, args, options) {
                const cmdStr = [file].concat(args || []).join(' ').toLowerCase();

                if (cmdStr.includes('reg') && cmdStr.includes('machineguid')) {
                    log('Intercepted MachineGuid query (execFileSync)');
                    return Buffer.from(`\r\n    MachineGuid    REG_SZ    ${getMachineGuid()}\r\n`);
                }

                if (cmdStr.includes('ioreg') && cmdStr.includes('ioplatformexpertdevice')) {
                    log('Intercepted IOPlatformUUID query (execFileSync)');
                    return Buffer.from(`"IOPlatformUUID" = "${getMachineGuid().toUpperCase()}"`);
                }

                if (cmdStr.includes('machine-id') || cmdStr.includes('hostname')) {
                    log('Intercepted machine-id query (execFileSync)');
                    return Buffer.from(__cursor_ids__.machineId.substring(0, 32));
                }

                return originalExecFileSync.apply(this, arguments);
            };
        }

        return cp;
    }

    // ==================== os Hook ====================

    function hookOs(os) {
        const originalNetworkInterfaces = os.networkInterfaces;

        os.networkInterfaces = function() {
            log('Intercepted networkInterfaces call');
            // Return virtual network interfaces with fixed MAC address
            return {
                'Ethernet': [{
                    address: '192.168.1.100',
                    netmask: '255.255.255.0',
                    family: 'IPv4',
                    mac: __windsurf_ids__.macAddress || '00:00:00:00:00:00',
                    internal: false
                }]
            };
        };

        return os;
    }

    // ==================== fs Hook (new) ====================
    // 🔧 Intercept storage.json write operations, protect telemetry fields from being overwritten

    // List of telemetry fields to protect
    const PROTECTED_TELEMETRY_KEYS = [
        'telemetry.machineId',
        'telemetry.macMachineId',
        'telemetry.devDeviceId',
        'telemetry.sqmId'
    ];

    // Normalize filePath (compatible with string/Buffer/URL etc.)
    function normalizeFilePath(filePath) {
        try {
            if (filePath === undefined || filePath === null) return '';
            if (typeof filePath === 'string') return filePath;
            if (Buffer.isBuffer(filePath)) return filePath.toString('utf8');

            // WHATWG URL (fs supports URL objects)
            if (typeof filePath === 'object' && typeof filePath.href === 'string') {
                // Prefer converting file:// URL to local path, avoid passing "file:///..." string causing existsSync/readFileSync to fail
                if (typeof filePath.protocol === 'string' && filePath.protocol === 'file:') {
                    try {
                        const url = require('url');
                        if (url && typeof url.fileURLToPath === 'function') {
                            return url.fileURLToPath(filePath);
                        }
                    } catch (_) {
                        // ignore
                    }
                }
                return filePath.href;
            }

            return String(filePath);
        } catch (_) {
            return '';
        }
    }

    function previewValue(value) {
        try {
            const s = String(value);
            return s.length > 16 ? s.slice(0, 16) + '...' : s;
        } catch (_) {
            return '<unprintable>';
        }
    }

    // Convert write content to utf8 text, and provide a wrapper to write back as the "same type"
    function coerceContentToUtf8Text(content) {
        try {
            if (typeof content === 'string') {
                return { text: content, wrap: (s) => s };
            }
            if (Buffer.isBuffer(content)) {
                return { text: content.toString('utf8'), wrap: (s) => Buffer.from(s, 'utf8') };
            }
            // TypedArray / DataView
            if (content && typeof content === 'object') {
                if (content instanceof Uint8Array) {
                    // Buffer is also Uint8Array, but already handled above
                    const buf = Buffer.from(content);
                    return { text: buf.toString('utf8'), wrap: (s) => new Uint8Array(Buffer.from(s, 'utf8')) };
                }
                if (typeof ArrayBuffer !== 'undefined' && content instanceof ArrayBuffer) {
                    const buf = Buffer.from(content);
                    return { text: buf.toString('utf8'), wrap: (s) => Buffer.from(s, 'utf8') };
                }
                if (typeof ArrayBuffer !== 'undefined' && typeof ArrayBuffer.isView === 'function' && ArrayBuffer.isView(content)) {
                    const buf = Buffer.from(content.buffer, content.byteOffset, content.byteLength);
                    return { text: buf.toString('utf8'), wrap: (s) => Buffer.from(s, 'utf8') };
                }
            }
        } catch (_) {
            // ignore
        }
        return null;
    }

    // Check if path is storage.json
    function isStorageJsonPath(filePath) {
        const raw = normalizeFilePath(filePath);
        if (!raw) return false;
        const normalized = raw.replace(/\\/g, '/').toLowerCase();
        return normalized.includes('globalstorage/storage.json');
    }

    // Protect telemetry fields in storage.json
    function protectStorageJson(content, filePath) {
        if (!isStorageJsonPath(filePath)) return content;
        
        try {
            const fs = require('fs');
            const coerced = coerceContentToUtf8Text(content);
            if (!coerced) return content;

            let newData;
            try {
                newData = JSON.parse(coerced.text);
            } catch (_) {
                return content;
            }
            
            // If the written content is not a valid JSON object, return directly
            if (typeof newData !== 'object' || newData === null) {
                return content;
            }
            
            // Protection value priority:
            // 1) __windsurf_ids__ (Hook config / environment variables / auto-generated)
            // 2) Existing values in current storage.json
            // 3) Current write value (lowest)
            const protectedValues = {
                'telemetry.machineId': __windsurf_ids__ && __windsurf_ids__.machineId,
                'telemetry.macMachineId': __windsurf_ids__ && __windsurf_ids__.macMachineId,
                'telemetry.devDeviceId': __windsurf_ids__ && __windsurf_ids__.devDeviceId,
                'telemetry.sqmId': __windsurf_ids__ && __windsurf_ids__.sqmId
            };

            // Only read old file values as secondary fallback when Hook config is incomplete
            let existingProtected = {};
            const needExisting = PROTECTED_TELEMETRY_KEYS.some((k) => !(typeof protectedValues[k] === 'string' && protectedValues[k]));
            if (needExisting) {
                try {
                    if (fs.existsSync(filePath)) {
                        const existingText = fs.readFileSync(filePath, 'utf8');
                        const existing = JSON.parse(existingText);
                        if (existing && typeof existing === 'object') {
                            for (const key of PROTECTED_TELEMETRY_KEYS) {
                                if (typeof existing[key] === 'string' && existing[key]) {
                                    existingProtected[key] = existing[key];
                                }
                            }
                        }
                    }
                } catch (_) {
                    // ignore
                }
            }
            
            let modified = false;
            for (const key of PROTECTED_TELEMETRY_KEYS) {
                const fromIds = protectedValues[key];
                const desired = (typeof fromIds === 'string' && fromIds) ? fromIds
                    : (typeof existingProtected[key] === 'string' && existingProtected[key]) ? existingProtected[key]
                    : undefined;

                if (desired === undefined) {
                    continue;
                }

                // Plan B: Regardless of whether the write content contains the field, ensure the final value is stable (fill in if missing)
                if (newData[key] !== desired) {
                    log(`[fs Hook] Fixed ${key}: ${previewValue(newData[key])} -> ${previewValue(desired)}`);
                    newData[key] = desired;
                    modified = true;
                }
            }
            
            if (modified) {
                log('[fs Hook] storage.json telemetry fields protected');
                const nextText = JSON.stringify(newData, null, '\t');
                return coerced.wrap(nextText);
            }
        } catch (e) {
            const msg = e && e.message ? e.message : String(e);
            log('[fs Hook] Failed to process storage.json:', msg);
        }
        
        return content;
    }

    function hookFs(fsModule) {
        const originalWriteFileSync = fsModule.writeFileSync;
        const originalWriteFile = fsModule.writeFile;
        const originalAppendFileSync = fsModule.appendFileSync;
        const originalAppendFile = fsModule.appendFile;
        const originalCreateWriteStream = fsModule.createWriteStream;
        const originalOpenSync = fsModule.openSync;
        const originalOpen = fsModule.open;
        const originalCloseSync = fsModule.closeSync;
        const originalClose = fsModule.close;

        // fd tracking: cover open/close path (only for storage.json)
        const storageJsonFds = new Map();
        let inFdFix = false;

        const fixStorageJsonFile = (filePath) => {
            if (inFdFix) return;
            inFdFix = true;
            try {
                const current = fsModule.readFileSync(filePath, 'utf8');
                const next = protectStorageJson(current, filePath);
                if (typeof next === 'string' && next !== current) {
                    originalWriteFileSync.call(fsModule, filePath, next, 'utf8');
                    log('[fs Hook] close-fix: storage.json telemetry fields re-protected');
                }
            } catch (e) {
                const msg = e && e.message ? e.message : String(e);
                log('[fs Hook] close-fix failed:', msg);
            } finally {
                inFdFix = false;
            }
        };

        // Hook writeFileSync
        fsModule.writeFileSync = function(filePath, data, options) {
            const protectedData = protectStorageJson(data, filePath);
            return originalWriteFileSync.call(this, filePath, protectedData, options);
        };

        // Hook writeFile (async version)
        fsModule.writeFile = function(filePath, data, options, callback) {
            // Handle argument overloading: writeFile(path, data, callback) or writeFile(path, data, options, callback)
            if (typeof options === 'function') {
                callback = options;
                options = undefined;
            }
            const protectedData = protectStorageJson(data, filePath);
            return originalWriteFile.call(this, filePath, protectedData, options, callback);
        };

        // Hook promises API (fs.promises.writeFile)
        if (fsModule.promises) {
            const originalPromisesWriteFile = fsModule.promises.writeFile;
            fsModule.promises.writeFile = async function(filePath, data, options) {
                const protectedData = protectStorageJson(data, filePath);
                return originalPromisesWriteFile.call(this, filePath, protectedData, options);
            };

            if (typeof fsModule.promises.appendFile === 'function') {
                const originalPromisesAppendFile = fsModule.promises.appendFile;
                fsModule.promises.appendFile = async function(filePath, data, options) {
                    const protectedData = protectStorageJson(data, filePath);
                    return originalPromisesAppendFile.call(this, filePath, protectedData, options);
                };
            }
        }

        // Hook appendFileSync
        if (typeof originalAppendFileSync === 'function') {
            fsModule.appendFileSync = function(filePath, data, options) {
                const protectedData = protectStorageJson(data, filePath);
                return originalAppendFileSync.call(this, filePath, protectedData, options);
            };
        }

        // Hook appendFile (async version)
        if (typeof originalAppendFile === 'function') {
            fsModule.appendFile = function(filePath, data, options, callback) {
                if (typeof options === 'function') {
                    callback = options;
                    options = undefined;
                }
                const protectedData = protectStorageJson(data, filePath);
                return originalAppendFile.call(this, filePath, protectedData, options, callback);
            };
        }

        // Hook createWriteStream (only for storage.json: keep native WriteStream, but do remedial fix after close)
        if (typeof originalCreateWriteStream === 'function') {
            fsModule.createWriteStream = function(filePath, options) {
                const stream = originalCreateWriteStream.apply(this, arguments);
                if (isStorageJsonPath(filePath) && stream && typeof stream.on === 'function') {
                    stream.on('close', () => {
                        try {
                            fixStorageJsonFile(filePath);
                        } catch (_) {
                            // ignore
                        }
                    });
                }
                return stream;
            };
        }

        // Hook open/openSync: track storage.json fd
        if (typeof originalOpenSync === 'function') {
            fsModule.openSync = function(filePath) {
                const fd = originalOpenSync.apply(this, arguments);
                try {
                    if (!inFdFix && isStorageJsonPath(filePath)) {
                        storageJsonFds.set(fd, filePath);
                    }
                } catch (_) {
                    // ignore
                }
                return fd;
            };
        }

        if (typeof originalOpen === 'function') {
            fsModule.open = function(filePath, flags, mode, callback) {
                if (typeof mode === 'function') {
                    callback = mode;
                    mode = undefined;
                }

                const wrapped = function(err, fd) {
                    try {
                        if (!err && !inFdFix && isStorageJsonPath(filePath)) {
                            storageJsonFds.set(fd, filePath);
                        }
                    } catch (_) {
                        // ignore
                    }
                    if (typeof callback === 'function') {
                        return callback.apply(this, arguments);
                    }
                };

                if (mode === undefined) {
                    return originalOpen.call(this, filePath, flags, wrapped);
                }
                return originalOpen.call(this, filePath, flags, mode, wrapped);
            };
        }

        // Hook close/closeSync: do a "post-flush fix" after close (cover fd write path)
        if (typeof originalCloseSync === 'function') {
            fsModule.closeSync = function(fd) {
                const filePath = storageJsonFds.get(fd);
                const ret = originalCloseSync.apply(this, arguments);
                if (filePath !== undefined) {
                    storageJsonFds.delete(fd);
                    fixStorageJsonFile(filePath);
                }
                return ret;
            };
        }

        if (typeof originalClose === 'function') {
            fsModule.close = function(fd, callback) {
                const filePath = storageJsonFds.get(fd);
                const wrapped = function(err) {
                    try {
                        if (!err && filePath !== undefined) {
                            storageJsonFds.delete(fd);
                            fixStorageJsonFile(filePath);
                        }
                    } catch (_) {
                        // ignore
                    }
                    if (typeof callback === 'function') {
                        return callback.apply(this, arguments);
                    }
                };
                return originalClose.call(this, fd, wrapped);
            };
        }

        log('[fs Hook] storage.json write protection enabled');
        return fsModule;
    }

    // ==================== crypto Hook ====================

    function hookCrypto(crypto) {
        const originalCreateHash = crypto.createHash;
        const originalRandomUUID = crypto.randomUUID;

        // Hook createHash - used to intercept machineId SHA256 calculation
        crypto.createHash = function(algorithm) {
            const hash = originalCreateHash.apply(this, arguments);

            if (algorithm.toLowerCase() === 'sha256') {
                const originalUpdate = hash.update.bind(hash);
                const originalDigest = hash.digest.bind(hash);

                let inputData = '';

                hash.update = function(data, encoding) {
                    inputData += String(data);
                    return originalUpdate(data, encoding);
                };

                hash.digest = function(encoding) {
                        // Check if this is a machineId-related hash calculation
                        if (inputData.includes('MachineGuid') ||
                            inputData.includes('IOPlatformUUID') ||
                            inputData.length === 32 ||
                            inputData.length === 36) {
                            log('Intercepted SHA256 hash calculation, returning fixed machineId');
                            if (encoding === 'hex') {
                                return __windsurf_ids__.machineId;
                            }
                            return Buffer.from(__windsurf_ids__.machineId, 'hex');
                        }
                    return originalDigest(encoding);
                };
            }

            return hash;
        };

        // Hook randomUUID - used to intercept devDeviceId generation
        if (originalRandomUUID) {
            let uuidCallCount = 0;
            crypto.randomUUID = function() {
                uuidCallCount++;
                // First call returns fixed devDeviceId
                if (uuidCallCount <= 2) {
                    log('Intercepted randomUUID call, returning fixed devDeviceId');
                    return __windsurf_ids__.devDeviceId;
                }
                return originalRandomUUID.apply(this, arguments);
            };
        }

        return crypto;
    }

    // ==================== @vscode/deviceid Hook ====================

    function hookDeviceId(deviceIdModule) {
        log('Hook @vscode/deviceid module');

        return {
            ...deviceIdModule,
            getDeviceId: async function() {
                log('Intercepted getDeviceId call');
                return __windsurf_ids__.devDeviceId;
            }
        };
    }

    // ==================== @vscode/windows-registry Hook ====================

    function hookWindowsRegistry(registryModule) {
        log('Hook @vscode/windows-registry module');

        const originalGetStringRegKey = registryModule.GetStringRegKey;

        return {
            ...registryModule,
            GetStringRegKey: function(hive, path, name) {
                const pathStr = (typeof path === 'string') ? path : '';
                // Intercept MachineId read
                if (name === 'MachineId' || pathStr.includes('SQMClient')) {
                    log('Intercepted registry MachineId/SQMClient read');
                    return __windsurf_ids__.sqmId;
                }
                // Intercept MachineGuid read
                if (name === 'MachineGuid' || pathStr.includes('Cryptography')) {
                    log('Intercepted registry MachineGuid read');
                    return getMachineGuid();
                }
                if (typeof originalGetStringRegKey === 'function') {
                    return originalGetStringRegKey.apply(this, arguments) || '';
                }
                return '';
            }
        };
    }

    // ==================== Dynamic import Hook ====================

    // Cursor uses dynamic import() to load modules, we need to Hook these modules
    // Due to ES Module restrictions, we implement this by Hooking global objects

    // Store hooked dynamic import modules
    const hookedDynamicModules = new Map();

    // Hook crypto module dynamic import
    const hookDynamicCrypto = (cryptoModule) => {
        if (hookedDynamicModules.has('crypto')) {
            return hookedDynamicModules.get('crypto');
        }

        const hooked = { ...cryptoModule };

        // Hook createHash
        if (cryptoModule.createHash) {
            const originalCreateHash = cryptoModule.createHash;
            hooked.createHash = function(algorithm) {
                const hash = originalCreateHash.apply(this, arguments);

                if (algorithm.toLowerCase() === 'sha256') {
                    const originalDigest = hash.digest.bind(hash);
                    let inputData = '';

                    const originalUpdate = hash.update.bind(hash);
                    hash.update = function(data, encoding) {
                        inputData += String(data);
                        return originalUpdate(data, encoding);
                    };

                    hash.digest = function(encoding) {
                        // Detect machineId-related hash
                        if (inputData.includes('MachineGuid') ||
                            inputData.includes('IOPlatformUUID') ||
                            (inputData.length >= 32 && inputData.length <= 40)) {
                            log('Dynamic import: Intercepted SHA256 hash');
                            return encoding === 'hex' ? __windsurf_ids__.machineId : Buffer.from(__windsurf_ids__.machineId, 'hex');
                        }
                        return originalDigest(encoding);
                    };
                }
                return hash;
            };
        }

        hookedDynamicModules.set('crypto', hooked);
        return hooked;
    };

    // Hook @vscode/deviceid module dynamic import
    const hookDynamicDeviceId = (deviceIdModule) => {
        if (hookedDynamicModules.has('@vscode/deviceid')) {
            return hookedDynamicModules.get('@vscode/deviceid');
        }

        const hooked = {
            ...deviceIdModule,
            getDeviceId: async () => {
                log('Dynamic import: Intercepted getDeviceId');
                return __windsurf_ids__.devDeviceId;
            }
        };

        hookedDynamicModules.set('@vscode/deviceid', hooked);
        return hooked;
    };

    // Hook @vscode/windows-registry module dynamic import
    const hookDynamicWindowsRegistry = (registryModule) => {
        if (hookedDynamicModules.has('@vscode/windows-registry')) {
            return hookedDynamicModules.get('@vscode/windows-registry');
        }

        const originalGetStringRegKey = registryModule.GetStringRegKey;
        const hooked = {
            ...registryModule,
            GetStringRegKey: function(hive, path, name) {
                const pathStr = (typeof path === 'string') ? path : '';
                if (name === 'MachineId' || pathStr.includes('SQMClient')) {
                    log('Dynamic import: Intercepted SQMClient');
                    return __windsurf_ids__.sqmId;
                }
                if (name === 'MachineGuid' || pathStr.includes('Cryptography')) {
                    log('Dynamic import: Intercepted MachineGuid');
                    return getMachineGuid();
                }
                if (typeof originalGetStringRegKey === 'function') {
                    return originalGetStringRegKey.apply(this, arguments) || '';
                }
                return '';
            }
        };

        hookedDynamicModules.set('@vscode/windows-registry', hooked);
        return hooked;
    };

    // Hook fs module dynamic import (new: protect storage.json)
    const hookDynamicFs = (fsModule) => {
        if (hookedDynamicModules.has('fs')) {
            return hookedDynamicModules.get('fs');
        }

        const hooked = { ...fsModule };
        const originalWriteFileSync = fsModule.writeFileSync;
        const originalWriteFile = fsModule.writeFile;
        const originalAppendFileSync = fsModule.appendFileSync;
        const originalAppendFile = fsModule.appendFile;
        const originalCreateWriteStream = fsModule.createWriteStream;
        const originalOpenSync = fsModule.openSync;
        const originalOpen = fsModule.open;
        const originalCloseSync = fsModule.closeSync;
        const originalClose = fsModule.close;

        const storageJsonFds = new Map();
        let inFdFix = false;

        const fixStorageJsonFile = (filePath) => {
            if (inFdFix) return;
            inFdFix = true;
            try {
                const current = fsModule.readFileSync(filePath, 'utf8');
                const next = protectStorageJson(current, filePath);
                if (typeof next === 'string' && next !== current) {
                    originalWriteFileSync.call(fsModule, filePath, next, 'utf8');
                    log('Dynamic import: close-fix storage.json telemetry fields re-protected');
                }
            } catch (e) {
                const msg = e && e.message ? e.message : String(e);
                log('Dynamic import: close-fix failed:', msg);
            } finally {
                inFdFix = false;
            }
        };

        hooked.writeFileSync = function(filePath, data, options) {
            const protectedData = protectStorageJson(data, filePath);
            return originalWriteFileSync.call(this, filePath, protectedData, options);
        };

        hooked.writeFile = function(filePath, data, options, callback) {
            if (typeof options === 'function') {
                callback = options;
                options = undefined;
            }
            const protectedData = protectStorageJson(data, filePath);
            return originalWriteFile.call(this, filePath, protectedData, options, callback);
        };

        // Hook promises API
        if (fsModule.promises) {
            const originalPromisesWriteFile = fsModule.promises.writeFile;
            hooked.promises = {
                ...fsModule.promises,
                writeFile: async function(filePath, data, options) {
                    const protectedData = protectStorageJson(data, filePath);
                    return originalPromisesWriteFile.call(this, filePath, protectedData, options);
                }
            };

            if (typeof fsModule.promises.appendFile === 'function') {
                const originalPromisesAppendFile = fsModule.promises.appendFile;
                hooked.promises.appendFile = async function(filePath, data, options) {
                    const protectedData = protectStorageJson(data, filePath);
                    return originalPromisesAppendFile.call(this, filePath, protectedData, options);
                };
            }
        }

        if (typeof originalAppendFileSync === 'function') {
            hooked.appendFileSync = function(filePath, data, options) {
                const protectedData = protectStorageJson(data, filePath);
                return originalAppendFileSync.call(this, filePath, protectedData, options);
            };
        }

        if (typeof originalAppendFile === 'function') {
            hooked.appendFile = function(filePath, data, options, callback) {
                if (typeof options === 'function') {
                    callback = options;
                    options = undefined;
                }
                const protectedData = protectStorageJson(data, filePath);
                return originalAppendFile.call(this, filePath, protectedData, options, callback);
            };
        }

        if (typeof originalCreateWriteStream === 'function') {
            hooked.createWriteStream = function(filePath, options) {
                const stream = originalCreateWriteStream.apply(this, arguments);
                if (isStorageJsonPath(filePath) && stream && typeof stream.on === 'function') {
                    stream.on('close', () => {
                        try {
                            fixStorageJsonFile(filePath);
                        } catch (_) {
                            // ignore
                        }
                    });
                }
                return stream;
            };
        }

        if (typeof originalOpenSync === 'function') {
            hooked.openSync = function(filePath) {
                const fd = originalOpenSync.apply(this, arguments);
                try {
                    if (!inFdFix && isStorageJsonPath(filePath)) {
                        storageJsonFds.set(fd, filePath);
                    }
                } catch (_) {
                    // ignore
                }
                return fd;
            };
        }

        if (typeof originalOpen === 'function') {
            hooked.open = function(filePath, flags, mode, callback) {
                if (typeof mode === 'function') {
                    callback = mode;
                    mode = undefined;
                }

                const wrapped = function(err, fd) {
                    try {
                        if (!err && !inFdFix && isStorageJsonPath(filePath)) {
                            storageJsonFds.set(fd, filePath);
                        }
                    } catch (_) {
                        // ignore
                    }
                    if (typeof callback === 'function') {
                        return callback.apply(this, arguments);
                    }
                };

                if (mode === undefined) {
                    return originalOpen.call(this, filePath, flags, wrapped);
                }
                return originalOpen.call(this, filePath, flags, mode, wrapped);
            };
        }

        if (typeof originalCloseSync === 'function') {
            hooked.closeSync = function(fd) {
                const filePath = storageJsonFds.get(fd);
                const ret = originalCloseSync.apply(this, arguments);
                if (filePath !== undefined) {
                    storageJsonFds.delete(fd);
                    fixStorageJsonFile(filePath);
                }
                return ret;
            };
        }

        if (typeof originalClose === 'function') {
            hooked.close = function(fd, callback) {
                const filePath = storageJsonFds.get(fd);
                const wrapped = function(err) {
                    try {
                        if (!err && filePath !== undefined) {
                            storageJsonFds.delete(fd);
                            fixStorageJsonFile(filePath);
                        }
                    } catch (_) {
                        // ignore
                    }
                    if (typeof callback === 'function') {
                        return callback.apply(this, arguments);
                    }
                };
                return originalClose.call(this, fd, wrapped);
            };
        }

        log('Dynamic import: Hooked fs module');
        hookedDynamicModules.set('fs', hooked);
        return hooked;
    };

    // Expose Hook functions globally for later use
    globalThis.__windsurf_hook_dynamic__ = {
        crypto: hookDynamicCrypto,
        deviceId: hookDynamicDeviceId,
        windowsRegistry: hookDynamicWindowsRegistry,
        fs: hookDynamicFs,  // New fs Hook
        ids: __windsurf_ids__
    };

    log('Windsurf Hook initialization complete');
    log('machineId:', __windsurf_ids__.machineId.substring(0, 16) + '...');
    log('machineGuid:', getMachineGuid().substring(0, 16) + '...');
    log('devDeviceId:', __windsurf_ids__.devDeviceId);
    log('sqmId:', __windsurf_ids__.sqmId);

})();

// ==================== Export configuration (for external use) ====================
if (typeof module !== 'undefined' && module.exports) {
    module.exports = { __windsurf_hook_config__ };
}

// ==================== ES Module Compatibility ====================
// If in ES Module environment, also expose configuration
if (typeof globalThis !== 'undefined') {
    globalThis.__windsurf_hook_config__ = __windsurf_hook_config__;
}
