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
    httpRequestPOST: (url, json, contentType = null, headers = null) => {
        return new Promise((resolve) => {
            let callId = window.boundobject.__manager.addCallback((data) => {
                resolve(data);
            });
            let newHeaders = {};
            for (let obj of headers ? JSON.parse(headers) : []) {
                let name = obj.name;
                let value = obj.value;
                newHeaders[name] = value;
            }
            newHeaders['Content-Type'] = contentType ? contentType : 'application/json';
            window.boundobject.__manager.callNative('httpRequestPOST', {
                url: url,
                body: typeof json === "string" ? json : JSON.stringify(json),
                headers: newHeaders
            }, callId);
        });
    },
    changeServURL: (newURL) => {
        window.boundobject.__manager.callNative('changeServerURL', {
            url: newURL
        });
    },
    saveCache: (fileName, content) => {
        content = Array.from(content);
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
        content = Array.from(content);
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
    setWebAudioPlaying: (playing) => {
        window.boundobject.__manager.callNative('setWebAudioPlaying', { playing: !!playing });
    },
    setRestoreMute: (mute) => {
        window.boundobject.__manager.callNative('setRestoreMute', { mute: !!mute });
    },
    notifyReady: () => {
        window.boundobject.__manager.callNative('appReady', {});
    },
    playMediaFrame: (taskId) => {
        return new Promise((resolve) => {
            let callId = window.boundobject.__manager.addCallback((data) => {
                resolve(data);
            });
            window.boundobject.__manager.callNative('playMediaFrame', {
                taskId: taskId
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
                name: cookieName
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
    },
    onUpdateStateChange: (callback) => {
        console.error("onUpdateStateChange is not implemented yet");
    },
    searchUpdates: () => {
        console.error("searchUpdates is not implemented yet");
    },
    getIframeStatus: (url) => {
        return new Promise((resolve) => {
            let callId = window.boundobject.__manager.addCallback((data) => {
                resolve(data);
            });
            window.boundobject.__manager.callNative('getIframeStatus', {
                url: url
            }, callId);
        });
    }
};

// Runs in EVERY frame (injected with forMainFrameOnly: false), including cross-origin iframes such as the
// Spotify Web Playback SDK frame nested inside the platform iframe.
(function () {
    try {
        const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.boundobject;
        if (!handler) return;
        const post = (method, params) => { try { handler.postMessage({ method: method, params: params || {}, callId: null }); } catch (e) { } };

        // 1. Let native know this frame exists: native can then run JS in it with a forced user gesture
        //    (WebKit denies audible playback in a hidden document that has no user activation, per document)
        post('registerFrame', { url: location.href, top: window === window.top });

        // 2. In a hidden page (background launch from Control Center) WebKit may refuse or silently swallow a play().
        //    evaluateJavaScript only gives a user gesture while the evaluated script runs, so native calls
        //    __aymusicRetryPlay() inside such a script to replay the elements that have not reached 'playing'.
        const origPlay = HTMLMediaElement.prototype.play;
        // Restore mute (see AudioManager.setRestoreMute)
        const mutedByUs = new Set();
        window.__aymMute = false;
        window.__aymSetMute = (mute) => {
            window.__aymMute = mute;
            if (!mute) {
                for (const el of mutedByUs) el.muted = false;
                mutedByUs.clear();
            }
        };
        const pending = new Set();    // play() was refused
        const attempted = new Set();  // play() was called while hidden and has not reached 'playing' yet
        const watch = (el) => {
            if (el.__aymWatched) return;
            el.__aymWatched = true;
            // playing / paused / ended: nothing left to replay
            for (const ev of ["playing", "pause", "ended", "emptied"]) {
                el.addEventListener(ev, () => { attempted.delete(el); if (ev !== "emptied") pending.delete(el); });
            }
        };
        HTMLMediaElement.prototype.play = function () {
            const el = this;
            watch(el);
            if (window.__aymMute && window !== window.top && !el.muted) {
                el.muted = true;
                mutedByUs.add(el);
            }
            const p = origPlay.apply(this, arguments);
            if (document.visibilityState !== "visible") {
                attempted.add(el);
                post('mediaPlayAttempt', {});
            }
            if (p && typeof p.then === "function") {
                return p.then((v) => { pending.delete(el); return v; }, (e) => { pending.add(el); throw e; });
            }
            return p;
        };
        window.__aymusicRetryPlay = async () => {
            for (const el of Array.from(new Set([...pending, ...attempted]))) {
                try {
                    await Promise.race([origPlay.call(el), new Promise((_, rej) => setTimeout(rej, 2000))]);
                    pending.delete(el);
                    attempted.delete(el);
                } catch (e) { }
            }
        };
    } catch (e) { }
})();
