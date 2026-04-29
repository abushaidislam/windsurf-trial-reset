/**
 * Windsurf 设备标识符 Hook 模块
 *
 * 🎯 功能：从底层拦截所有设备标识符的生成，实现一劳永逸的机器码修改
 *
 * 🔧 Hook 点：
 * 1. child_process.execSync - 拦截 REG.exe 查询 MachineGuid
 * 2. crypto.createHash - 拦截 SHA256 哈希计算
 * 3. @vscode/deviceid - 拦截 devDeviceId 获取
 * 4. @vscode/windows-registry - 拦截注册表读取
 * 5. os.networkInterfaces - 拦截 MAC 地址获取
 * 6. fs.writeFileSync/writeFile - 拦截 storage.json 写入，保护 telemetry 字段
 *
 * 📦 使用方式：
 * 将此代码注入到 main.js 文件顶部（Sentry 初始化之后）
 *
 * ⚙️ 配置方式：
 * 1. 环境变量：WINDSURF_MACHINE_ID, WINDSURF_MAC_MACHINE_ID, WINDSURF_DEV_DEVICE_ID, WINDSURF_SQM_ID
 * 2. 配置文件：~/.windsurf_ids.json
 * 3. 自动生成：如果没有配置，则自动生成并持久化
 */

// ==================== 配置区域 ====================
// 使用 var 确保在 ES Module 环境中也能正常工作
var __windsurf_hook_config__ = {
    // 是否启用 Hook（设置为 false 可临时禁用）
    enabled: true,
    // 是否输出调试日志（设置为 true 可查看详细日志）
    debug: false,
    // 配置文件路径（相对于用户目录）
    configFileName: '.windsurf_ids.json',
    // 标记：防止重复注入
    injected: false
};

// ==================== Hook 实现 ====================
// 使用 IIFE 确保代码立即执行
(function() {
    'use strict';

    // 防止重复注入
    if (globalThis.__windsurf_patched__ || __windsurf_hook_config__.injected) {
        return;
    }
    globalThis.__windsurf_patched__ = true;
    __windsurf_hook_config__.injected = true;

    // 调试日志函数
    const log = (...args) => {
        if (__windsurf_hook_config__.debug) {
            console.log('[WindsurfHook]', ...args);
        }
    };

    // ==================== ID 生成和管理 ====================

    // 生成 UUID v4
    const generateUUID = () => {
        return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
            const r = Math.random() * 16 | 0;
            const v = c === 'x' ? r : (r & 0x3 | 0x8);
            return v.toString(16);
        });
    };

    // 生成 64 位十六进制字符串（用于 machineId）
    const generateHex64 = () => {
        let hex = '';
        for (let i = 0; i < 64; i++) {
            hex += Math.floor(Math.random() * 16).toString(16);
        }
        return hex;
    };

    // 生成 MAC 地址格式的字符串
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

    // 加载或生成 ID 配置
    // 注意：该 Hook 由脚本注入的 Loader 通过 CommonJS(require) 方式加载，
    // 为避免出现 import.meta 等仅 ESM 支持的语法导致 Cursor 启动期解析失败，这里保持纯 CommonJS 写法。
    const loadOrGenerateIds = () => {
        const fs = require('fs');
        const path = require('path');
        const os = require('os');

        const configPath = path.join(os.homedir(), __windsurf_hook_config__.configFileName);

        let ids = null;

        // 尝试从环境变量读取
        if (process.env.WINDSURF_MACHINE_ID) {
            ids = {
                machineId: process.env.WINDSURF_MACHINE_ID,
                // machineGuid 用于模拟注册表 MachineGuid/IOPlatformUUID
                machineGuid: process.env.WINDSURF_MACHINE_GUID || generateUUID(),
                macMachineId: process.env.WINDSURF_MAC_MACHINE_ID || generateHex64(),
                devDeviceId: process.env.WINDSURF_DEV_DEVICE_ID || generateUUID(),
                sqmId: process.env.WINDSURF_SQM_ID || `{${generateUUID().toUpperCase()}}`,
                macAddress: process.env.WINDSURF_MAC_ADDRESS || generateMacAddress(),
                sessionId: process.env.WINDSURF_SESSION_ID || generateUUID(),
                firstSessionDate: process.env.WINDSURF_FIRST_SESSION_DATE || new Date().toISOString()
            };
            log('从环境变量加载 ID 配置');
            return ids;
        }

        // 尝试从配置文件读取
        try {
            if (fs.existsSync(configPath)) {
                const content = fs.readFileSync(configPath, 'utf8');
                ids = JSON.parse(content);
                // 补全缺失字段，保持向后兼容
                let updated = false;
                // 🔧 补齐核心 ID 字段（用于 Hook 与 storage.json 保护）
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
                        log('已补全并更新 ID 配置:', configPath);
                    } catch (e) {
                        log('补全配置文件失败:', e.message);
                    }
                }
                log('从配置文件加载 ID 配置:', configPath);
                return ids;
            }
        } catch (e) {
            log('读取配置文件失败:', e.message);
        }

        // 生成新的 ID
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

        // 保存到配置文件
        try {
            fs.writeFileSync(configPath, JSON.stringify(ids, null, 2), 'utf8');
            log('已生成并保存新的 ID 配置:', configPath);
        } catch (e) {
            log('保存配置文件失败:', e.message);
        }

        return ids;
    };

    // 加载 ID 配置
    const __windsurf_ids__ = loadOrGenerateIds();
    // 统一获取 MachineGuid，缺失时回退到 machineId 的前 36 位
    const getMachineGuid = () => __windsurf_ids__.machineGuid || __windsurf_ids__.machineId.substring(0, 36);
    log('当前 ID 配置:', __windsurf_ids__);
    
    // ==================== Module Hook ====================
    
    const Module = require('module');
    const originalRequire = Module.prototype.require;
    
    // 缓存已 Hook 的模块
    const hookedModules = new Map();
    
    Module.prototype.require = function(id) {
        // 兼容 node: 前缀
        const normalizedId = (typeof id === 'string' && id.startsWith('node:')) ? id.slice(5) : id;
        const result = originalRequire.apply(this, arguments);
        
        // 如果已经 Hook 过，直接返回缓存
        if (hookedModules.has(normalizedId)) {
            return hookedModules.get(normalizedId);
        }
        
        let hooked = result;
        
        // Hook child_process 模块
        if (normalizedId === 'child_process') {
            hooked = hookChildProcess(result);
        }
        // Hook os 模块
        else if (normalizedId === 'os') {
            hooked = hookOs(result);
        }
        // Hook fs 模块 (新增：保护 storage.json)
        else if (normalizedId === 'fs') {
            hooked = hookFs(result);
        }
        // Hook crypto 模块
        else if (normalizedId === 'crypto') {
            hooked = hookCrypto(result);
        }
        // Hook @vscode/deviceid 模块
        else if (normalizedId === '@vscode/deviceid') {
            hooked = hookDeviceId(result);
        }
        // Hook @vscode/windows-registry 模块
        else if (normalizedId === '@vscode/windows-registry') {
            hooked = hookWindowsRegistry(result);
        }

        // 缓存 Hook 结果
        if (hooked !== result) {
            hookedModules.set(normalizedId, hooked);
            log(`已 Hook 模块: ${normalizedId}`);
        }
        
        return hooked;
    };

    // ==================== child_process Hook ====================

    function hookChildProcess(cp) {
        const originalExecSync = cp.execSync;
        const originalExecFileSync = cp.execFileSync;

        cp.execSync = function(command, options) {
            const cmdStr = String(command).toLowerCase();

            // 拦截 MachineGuid 查询
            if (cmdStr.includes('reg') && cmdStr.includes('machineguid')) {
                log('拦截 MachineGuid 查询');
                // 返回格式化的注册表输出
                return Buffer.from(`\r\n    MachineGuid    REG_SZ    ${getMachineGuid()}\r\n`);
            }

            // 拦截 ioreg 命令 (macOS)
            if (cmdStr.includes('ioreg') && cmdStr.includes('ioplatformexpertdevice')) {
                log('拦截 IOPlatformUUID 查询');
                return Buffer.from(`"IOPlatformUUID" = "${getMachineGuid().toUpperCase()}"`);
            }

            // 拦截 machine-id 读取 (Linux)
            if (cmdStr.includes('machine-id') || cmdStr.includes('hostname')) {
                log('拦截 machine-id 查询');
                return Buffer.from(__windsurf_ids__.machineId.substring(0, 32));
            }

            return originalExecSync.apply(this, arguments);
        };

        // 兼容 execFileSync（部分版本会直接调用可执行文件）
        if (typeof originalExecFileSync === 'function') {
            cp.execFileSync = function(file, args, options) {
                const cmdStr = [file].concat(args || []).join(' ').toLowerCase();

                if (cmdStr.includes('reg') && cmdStr.includes('machineguid')) {
                    log('拦截 MachineGuid 查询(execFileSync)');
                    return Buffer.from(`\r\n    MachineGuid    REG_SZ    ${getMachineGuid()}\r\n`);
                }

                if (cmdStr.includes('ioreg') && cmdStr.includes('ioplatformexpertdevice')) {
                    log('拦截 IOPlatformUUID 查询(execFileSync)');
                    return Buffer.from(`"IOPlatformUUID" = "${getMachineGuid().toUpperCase()}"`);
                }

                if (cmdStr.includes('machine-id') || cmdStr.includes('hostname')) {
                    log('拦截 machine-id 查询(execFileSync)');
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
            log('拦截 networkInterfaces 调用');
            // 返回虚拟的网络接口，使用固定的 MAC 地址
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

    // ==================== fs Hook (新增) ====================
    // 🔧 拦截 storage.json 写入操作，保护 telemetry 字段不被覆盖

    // 需要保护的 telemetry 字段列表
    const PROTECTED_TELEMETRY_KEYS = [
        'telemetry.machineId',
        'telemetry.macMachineId',
        'telemetry.devDeviceId',
        'telemetry.sqmId'
    ];

    // 规范化 filePath（兼容 string/Buffer/URL 等）
    function normalizeFilePath(filePath) {
        try {
            if (filePath === undefined || filePath === null) return '';
            if (typeof filePath === 'string') return filePath;
            if (Buffer.isBuffer(filePath)) return filePath.toString('utf8');

            // WHATWG URL (fs 支持 URL 对象)
            if (typeof filePath === 'object' && typeof filePath.href === 'string') {
                // 优先将 file:// URL 转为本地路径，避免传递 "file:///..." 字符串导致 existsSync/readFileSync 失败
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

    // 将写入内容转为 utf8 文本，并提供回写为“同类类型”的包装器
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
                    // Buffer 也属于 Uint8Array，但已在上面处理
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

    // 检查路径是否为 storage.json
    function isStorageJsonPath(filePath) {
        const raw = normalizeFilePath(filePath);
        if (!raw) return false;
        const normalized = raw.replace(/\\/g, '/').toLowerCase();
        return normalized.includes('globalstorage/storage.json');
    }

    // 保护 storage.json 中的 telemetry 字段
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
            
            // 如果写入的内容不是有效的 JSON 对象，直接返回
            if (typeof newData !== 'object' || newData === null) {
                return content;
            }
            
            // 保护值优先级：
            // 1) __windsurf_ids__（Hook 配置/环境变量/自动生成）
            // 2) 现有 storage.json 中已存在的值
            // 3) 本次写入值（最低）
            const protectedValues = {
                'telemetry.machineId': __windsurf_ids__ && __windsurf_ids__.machineId,
                'telemetry.macMachineId': __windsurf_ids__ && __windsurf_ids__.macMachineId,
                'telemetry.devDeviceId': __windsurf_ids__ && __windsurf_ids__.devDeviceId,
                'telemetry.sqmId': __windsurf_ids__ && __windsurf_ids__.sqmId
            };

            // 仅当 Hook 配置不完整时，才读取旧文件值作为二级兜底
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

                // 方案B：无论写入内容是否包含该字段，都确保最终值稳定（缺失则补齐）
                if (newData[key] !== desired) {
                    log(`[fs Hook] 固定 ${key}: ${previewValue(newData[key])} -> ${previewValue(desired)}`);
                    newData[key] = desired;
                    modified = true;
                }
            }
            
            if (modified) {
                log('[fs Hook] storage.json telemetry 字段已保护');
                const nextText = JSON.stringify(newData, null, '\t');
                return coerced.wrap(nextText);
            }
        } catch (e) {
            const msg = e && e.message ? e.message : String(e);
            log('[fs Hook] 处理 storage.json 失败:', msg);
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

        // fd 追踪：覆盖 open/close 路径（仅用于 storage.json）
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
                    log('[fs Hook] close-fix: storage.json telemetry 字段已重新保护');
                }
            } catch (e) {
                const msg = e && e.message ? e.message : String(e);
                log('[fs Hook] close-fix 失败:', msg);
            } finally {
                inFdFix = false;
            }
        };

        // Hook writeFileSync
        fsModule.writeFileSync = function(filePath, data, options) {
            const protectedData = protectStorageJson(data, filePath);
            return originalWriteFileSync.call(this, filePath, protectedData, options);
        };

        // Hook writeFile (异步版本)
        fsModule.writeFile = function(filePath, data, options, callback) {
            // 处理参数重载: writeFile(path, data, callback) 或 writeFile(path, data, options, callback)
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

        // Hook appendFile (异步版本)
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

        // Hook createWriteStream（仅对 storage.json：保持原生 WriteStream，但 close 后做补救性修正）
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

        // Hook open/openSync：追踪 storage.json 的 fd
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

        // Hook close/closeSync：关闭后再做一次“落盘后修正”（覆盖 fd 写入路径）
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

        log('[fs Hook] 已启用 storage.json 写入保护');
        return fsModule;
    }

    // ==================== crypto Hook ====================

    function hookCrypto(crypto) {
        const originalCreateHash = crypto.createHash;
        const originalRandomUUID = crypto.randomUUID;

        // Hook createHash - 用于拦截 machineId 的 SHA256 计算
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
                        // 检查是否是 machineId 相关的哈希计算
                        if (inputData.includes('MachineGuid') ||
                            inputData.includes('IOPlatformUUID') ||
                            inputData.length === 32 ||
                            inputData.length === 36) {
                            log('拦截 SHA256 哈希计算，返回固定 machineId');
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

        // Hook randomUUID - 用于拦截 devDeviceId 生成
        if (originalRandomUUID) {
            let uuidCallCount = 0;
            crypto.randomUUID = function() {
                uuidCallCount++;
                // 第一次调用返回固定的 devDeviceId
                if (uuidCallCount <= 2) {
                    log('拦截 randomUUID 调用，返回固定 devDeviceId');
                    return __windsurf_ids__.devDeviceId;
                }
                return originalRandomUUID.apply(this, arguments);
            };
        }

        return crypto;
    }

    // ==================== @vscode/deviceid Hook ====================

    function hookDeviceId(deviceIdModule) {
        log('Hook @vscode/deviceid 模块');

        return {
            ...deviceIdModule,
            getDeviceId: async function() {
                log('拦截 getDeviceId 调用');
                return __windsurf_ids__.devDeviceId;
            }
        };
    }

    // ==================== @vscode/windows-registry Hook ====================

    function hookWindowsRegistry(registryModule) {
        log('Hook @vscode/windows-registry 模块');

        const originalGetStringRegKey = registryModule.GetStringRegKey;

        return {
            ...registryModule,
            GetStringRegKey: function(hive, path, name) {
                const pathStr = (typeof path === 'string') ? path : '';
                // 拦截 MachineId 读取
                if (name === 'MachineId' || pathStr.includes('SQMClient')) {
                    log('拦截注册表 MachineId/SQMClient 读取');
                    return __windsurf_ids__.sqmId;
                }
                // 拦截 MachineGuid 读取
                if (name === 'MachineGuid' || pathStr.includes('Cryptography')) {
                    log('拦截注册表 MachineGuid 读取');
                    return getMachineGuid();
                }
                if (typeof originalGetStringRegKey === 'function') {
                    return originalGetStringRegKey.apply(this, arguments) || '';
                }
                return '';
            }
        };
    }

    // ==================== 动态 import Hook ====================

    // Cursor 使用动态 import() 加载模块，我们需要 Hook 这些模块
    // 由于 ES Module 的限制，我们通过 Hook 全局对象来实现

    // 存储已 Hook 的动态导入模块
    const hookedDynamicModules = new Map();

    // Hook crypto 模块的动态导入
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
                        // 检测 machineId 相关的哈希
                        if (inputData.includes('MachineGuid') ||
                            inputData.includes('IOPlatformUUID') ||
                            (inputData.length >= 32 && inputData.length <= 40)) {
                            log('动态导入: 拦截 SHA256 哈希');
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

    // Hook @vscode/deviceid 模块的动态导入
    const hookDynamicDeviceId = (deviceIdModule) => {
        if (hookedDynamicModules.has('@vscode/deviceid')) {
            return hookedDynamicModules.get('@vscode/deviceid');
        }

        const hooked = {
            ...deviceIdModule,
            getDeviceId: async () => {
                log('动态导入: 拦截 getDeviceId');
                return __windsurf_ids__.devDeviceId;
            }
        };

        hookedDynamicModules.set('@vscode/deviceid', hooked);
        return hooked;
    };

    // Hook @vscode/windows-registry 模块的动态导入
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
                    log('动态导入: 拦截 SQMClient');
                    return __windsurf_ids__.sqmId;
                }
                if (name === 'MachineGuid' || pathStr.includes('Cryptography')) {
                    log('动态导入: 拦截 MachineGuid');
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

    // Hook fs 模块的动态导入 (新增：保护 storage.json)
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
                    log('动态导入: close-fix storage.json telemetry 字段已重新保护');
                }
            } catch (e) {
                const msg = e && e.message ? e.message : String(e);
                log('动态导入: close-fix 失败:', msg);
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

        log('动态导入: 已 Hook fs 模块');
        hookedDynamicModules.set('fs', hooked);
        return hooked;
    };

    // 将 Hook 函数暴露到全局，供后续使用
    globalThis.__windsurf_hook_dynamic__ = {
        crypto: hookDynamicCrypto,
        deviceId: hookDynamicDeviceId,
        windowsRegistry: hookDynamicWindowsRegistry,
        fs: hookDynamicFs,  // 新增 fs Hook
        ids: __windsurf_ids__
    };

    log('Windsurf Hook 初始化完成');
    log('machineId:', __windsurf_ids__.machineId.substring(0, 16) + '...');
    log('machineGuid:', getMachineGuid().substring(0, 16) + '...');
    log('devDeviceId:', __windsurf_ids__.devDeviceId);
    log('sqmId:', __windsurf_ids__.sqmId);

})();

// ==================== 导出配置（供外部使用） ====================
if (typeof module !== 'undefined' && module.exports) {
    module.exports = { __windsurf_hook_config__ };
}

// ==================== ES Module 兼容性 ====================
// 如果在 ES Module 环境中，也暴露配置
if (typeof globalThis !== 'undefined') {
    globalThis.__windsurf_hook_config__ = __windsurf_hook_config__;
}
