window.boundobject = {
    __manager: {
        callIdCounter: 0,
        callbackList: {},
        callNative: (method, params, callId) => {
            window.webkit.messageHandlers.boundobject.postMessage({
                method: method,
                params: params || {},
                callId: callId || null
            });
        },
        callbackNative: (callId, data) => {
            if (!callId || callId === 'cb_-1') return false;
            try {
                window.boundobject.__manager.callbackList[callId](data);
                delete window.boundobject.__manager.callbackList[callId];
                return true;
            }
            catch (e) {
                console.error('Callback error for callId ' + callId + ': ' + e);
                return false;
            }
        },
        addCallback: (callback) => {
            window.boundobject.__manager.callIdCounter += 1;
            let callId = 'cb_' + window.boundobject.__manager.callIdCounter + '_' + new Date().getTime();
            window.boundobject.__manager.callbackList[callId] = callback;
            return callId;
        },
    },
    getDeviceInfo: async () => {
        return new Promise((resolve) => {
            let callId = window.boundobject.__manager.addCallback((data) => {
                resolve(data);
            });
            window.boundobject.__manager.callNative('getDeviceInfo', {}, callId);
        });
    },
    getSettingFile: () => {
        return new Promise((resolve) => {
            let callId = window.boundobject.__manager.addCallback((data) => {
                resolve(data);
            });
            window.boundobject.__manager.callNative('getSettings', {
                fileName: 'UserSettings.json'
            }, callId);
        });
    },
    getUserSettingsFile: (file) => {
        return new Promise((resolve) => {
            let callId = window.boundobject.__manager.addCallback((data) => {
                resolve(data);
            });
            window.boundobject.__manager.callNative('getSettings', {
                fileName: file
            }, callId);
        });
    },
    changeSettingFile: (content) => {
        window.boundobject.__manager.callNative('setSettings', {
            fileName: 'UserSettings.json',
            content: content
        });
    },
    changeUserSettingsFile: (file, content) => {
        window.boundobject.__manager.callNative('setSettings', {
            fileName: file,
            content: content
        });
    },
    httpRequestGET: (url, options) => {
        return new Promise((resolve) => {
            let callId = window.boundobject.__manager.addCallback((data) => {
                resolve(data);
            });
            window.boundobject.__manager.callNative('httpRequestGET', {
                url: url,
                headers: options && options.headers ? options.headers : {}
            }, callId);
        });
    },
    httpRequestPOST: (url, body, options) => {
        return new Promise((resolve) => {
            let callId = window.boundobject.__manager.addCallback((data) => {
                resolve(data);
            });
            window.boundobject.__manager.callNative('httpRequestPOST', {
                url: url,
                body: body,
                headers: options && options.headers ? options.headers : {}
            }, callId);
        });
    },
    changeServURL: (newURL) => {
        window.boundobject.__manager.callNative('changeServerURL', {
            url: newURL
        });
    },
    saveCache: (fileName, content) => {
        window.boundobject.__manager.callNative('saveCache', {
            fileName: fileName,
            content: content
        });
    },
    removeCache: (fileName) => {
        return new Promise((resolve) => {
            let callId = window.boundobject.__manager.addCallback((data) => {
                resolve(data);
            });
            window.boundobject.__manager.callNative('removeCache', {
                fileName: fileName
            }, callId);
        });
    },
    saveData: (fileName, content) => {
        window.boundobject.__manager.callNative('saveData', {
            fileName: fileName,
            content: content
        });
    },
    removeData: (fileName) => {
        return new Promise((resolve) => {
            let callId = window.boundobject.__manager.addCallback((data) => {
                resolve(data);
            });
            window.boundobject.__manager.callNative('removeData', {
                fileName: fileName
            }, callId);
        });
    },
    registerIframeUrl: (url, code) => {
        window.boundobject.__manager.callNative('registerIframeUrl', {
            url: url,
            code: code
        });
    },
    haveCookie: (url, cookieName) => {
        return new Promise((resolve) => {
            let callId = window.boundobject.__manager.addCallback((data) => {
                resolve(data);
            });
            window.boundobject.__manager.callNative('haveCookie', {
                url: url,
                cookieName: cookieName
            }, callId);
        });
    },
    getWindowInsets: () => {
        return new Promise((resolve) => {
            let callId = window.boundobject.__manager.addCallback((data) => {
                resolve(data);
            });
            window.boundobject.__manager.callNative('getWindowInsets', {}, callId);
        });
    },
    cacheRequestBody: (url, bodyData) => {
        return new Promise((resolve) => {
            let callId = window.boundobject.__manager.addCallback((data) => {
                resolve(data);
            });
            window.boundobject.__manager.callNative('cacheRequestBody', {
                url: url,
                body: bodyData
            }, callId);
        });
    },
    registerOverrideResponse: (overrides) => {
        window.boundobject.__manager.callNative('registerOverrideResponse', {
            response: overrides
        });
    },
    clearOverrideResponses: () => {
        window.boundobject.__manager.callNative('clearOverrideResponses', {});
    },
    openWebsiteInNewWindow: (baseUrl, closeUrl, filterByInclude) => {
        return new Promise((resolve) => {
            let callId = window.boundobject.__manager.addCallback((data) => {
                resolve(data);
            });
            window.boundobject.__manager.callNative('openWebsiteInNewWindow', {
                baseUrl: baseUrl,
                closeUrl: closeUrl,
                filterByInclude: filterByInclude
            }, callId);
        });
    },
    getClientToken: (platform) => {
        return new Promise((resolve) => {
            let callId = window.boundobject.__manager.addCallback((data) => {
                resolve(data);
            });
            window.boundobject.__manager.callNative('getClientToken', {
                platform: platform
            }, callId);
        });
    },
    removeClientToken: (platform) => {
        window.boundobject.__manager.callNative('removeClientToken', {
            platform: platform
        });
    },
    clearWebViewCache: () => {
        window.boundobject.__manager.callNative('clearWebViewCache', {});
    },
    addBadUrl: (url, includes) => {
        window.boundobject.__manager.callNative('addBadUrl', {
            url: url,
            includes: includes
        });
    },
    pickUpMusic: () => {
        window.boundobject.__manager.callNative('pickUpMusic', {});
    },
    openLink: (url) => {
        window.boundobject.__manager.callNative('openLink', {
            url: url
        });
    },
    restartApp: () => {
        window.boundobject.__manager.callNative('restartApp', {});
    }
};
