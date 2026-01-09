(() => {
    function utf8ToBase64(str) {
        const encoder = new TextEncoder();
        const bytes = encoder.encode(str);
        let binary = '';
        for (let i = 0; i < bytes.length; i++) {
            binary += String.fromCharCode(bytes[i]);
        }
        return btoa(binary);
    }

    // Intercept fetch to cache POST body data
    const originalFetch = window.fetch;
    window.fetch = async function (url, options = {}) {
        try {
            // check if url is string or Request
            if (typeof url === 'string') {
                // Cache body data for POST/PUT/PATCH requests
                if (options.method && ['POST', 'PUT', 'PATCH'].includes(options.method.toUpperCase()) && options.body) {
                    let bodyData;
                    let isBase64 = false;

                    // Handle different body types
                    if (typeof options.body === 'string') {
                        bodyData = options.body;
                    } else if (options.body instanceof Blob) {
                        // Binary data (File, Blob) - convert to base64
                        const arrayBuffer = await options.body.arrayBuffer();
                        const bytes = new Uint8Array(arrayBuffer);
                        let binary = '';
                        for (let i = 0; i < bytes.length; i++) {
                            binary += String.fromCharCode(bytes[i]);
                        }
                        bodyData = btoa(binary);
                        isBase64 = true;
                    } else if (options.body instanceof ArrayBuffer) {
                        // ArrayBuffer - convert to base64
                        const bytes = new Uint8Array(options.body);
                        let binary = '';
                        for (let i = 0; i < bytes.length; i++) {
                            binary += String.fromCharCode(bytes[i]);
                        }
                        bodyData = btoa(binary);
                        isBase64 = true;
                    } else if (ArrayBuffer.isView(options.body)) {
                        // Typed arrays (Uint8Array, Int8Array, etc.) - used by protobuffer
                        // Convert to base64 to avoid JSON serialization issues
                        const bytes = new Uint8Array(options.body.buffer, options.body.byteOffset, options.body.byteLength);
                        let binary = '';
                        for (let i = 0; i < bytes.length; i++) {
                            binary += String.fromCharCode(bytes[i]);
                        }
                        bodyData = btoa(binary);
                        isBase64 = true;
                    } else if (options.body instanceof FormData) {
                        // FormData can't be easily serialized - let browser handle it
                        // Skip caching for FormData
                        console.warn('[IframeInjector] Skipping body cache for FormData');
                        bodyData = null;
                    } else if (options.body instanceof URLSearchParams) {
                        // URLSearchParams - convert to string
                        bodyData = options.body.toString();
                    } else {
                        // Object or other - convert to JSON
                        bodyData = JSON.stringify(options.body);
                    }

                    // Cache via boundobject with unique ID in header
                    if (bodyData) {
                        try {
                            options.headers.append('X-Body-Data', bodyData);
                            if (isBase64) options.headers.append('X-Body-Encoding', 'base64');
                        } catch (e) {
                            try {
                                // If headers is not a Headers object, create one
                                const newHeaders = new Headers(options.headers || {});
                                newHeaders.append('X-Body-Data', bodyData);
                                if (isBase64) newHeaders.append('X-Body-Encoding', 'base64');
                                options.headers = newHeaders;
                            } catch (e2) {
                                if (e2.name === 'TypeError') {
                                    const newHeaders = new Headers(options.headers || {});
                                    newHeaders.append('X-Body-Data', utf8ToBase64(bodyData));
                                    newHeaders.append('X-Body-Encoding', 'base64');
                                    options.headers = newHeaders;
                                }
                            }
                        }
                    }
                    else console.warn('[IframeInjector] bodyData not available');
                }
            } else if (url instanceof Request) {
                let requestUrl = url.url;
                let method = url.method;
                // Cache body data for POST/PUT/PATCH requests
                if (method && ['POST', 'PUT', 'PATCH'].includes(method.toUpperCase()) && url.body) {
                    // Clone the request to read the body without consuming the original
                    const clonedRequest = url.clone();
                    let bodyData;
                    let isBase64 = false;

                    // Try to read as text first
                    const contentType = url.headers.get('Content-Type') || '';
                    if (contentType.includes('application/json') || contentType.includes('text/')) {
                        bodyData = await clonedRequest.text();
                    } else {
                        // Binary data - convert to base64
                        const arrayBuffer = await clonedRequest.arrayBuffer();
                        const bytes = new Uint8Array(arrayBuffer);
                        let binary = '';
                        for (let i = 0; i < bytes.length; i++) {
                            binary += String.fromCharCode(bytes[i]);
                        }
                        bodyData = btoa(binary);
                        isBase64 = true;
                    }

                    // Cache via boundobject with unique ID in header
                    if (bodyData) {
                        // Create new Request with X-Body-Data header and explicit body                                
                        try {
                            url.headers.append('X-Body-Data', bodyData);
                            if (isBase64) url.headers.append('X-Body-Encoding', 'base64');
                        } catch (e) {
                            if (e.name === 'TypeError') {
                                url.headers.append('X-Body-Data', utf8ToBase64(bodyData));
                                url.headers.append('X-Body-Encoding', 'base64');
                            }
                        }
                    }
                    else console.warn('[IframeInjector] boundobject not available');
                }
            }

            // Call with modified url and options
            // For Request objects, don't pass options (Request already contains all config)

            // Add credentials marker to URL if credentials: 'include'
            if (typeof url === 'string') {
                if (options.credentials === 'include') {
                    url += (url.includes('?') ? '&' : '?') + '__credentials=true';
                }

                // Build final Headers object right before fetch to ensure all headers are captured
                const finalHeaders = new Headers(options.headers || {});

                // Create new options with the final Headers object
                const finalOptions = { ...options, headers: finalHeaders };
                return originalFetch(url, finalOptions);
            } else if (url instanceof Request) {
                if (url.credentials === 'include') {
                    const originalUrl = url.url;
                    const newUrl = originalUrl + (originalUrl.includes('?') ? '&' : '?') + '__credentials=true';

                    // https://stackoverflow.com/a/48713509
                    function newRequest(input, init = {}) {
                        var url = newUrl;
                        Object.keys(Request.prototype).forEach(function (value) {
                            init[value] = input[value];
                        });
                        delete init.url;

                        return input.blob().then(function (blob) {
                            if (input.method.toUpperCase() !== 'HEAD' && input.method.toUpperCase() !== 'GET' && blob.size > 0) {
                                init.body = blob;
                            }
                            return new Request(url, init);
                        });
                    }
                    let newReq = await newRequest(url);
                    return originalFetch(newReq);
                }
                else return originalFetch(url, options);
            }
            else return originalFetch(url, options);
        } catch (e) {
            console.error('[IframeInjector] Error in fetch interception:', e);
            return originalFetch(url, options);
        }
    };

    // Intercept XMLHttpRequest for older code
    const originalOpen = XMLHttpRequest.prototype.open;
    const originalSend = XMLHttpRequest.prototype.send;

    XMLHttpRequest.prototype.open = function (method, url, ...args) {
        this._method = method;
        this._url = url;

        // Add credentials marker to URL if withCredentials is true
        if (this.withCredentials) {
            url += (url.includes('?') ? '&' : '?') + '__credentials=true';
        }

        return originalOpen.apply(this, [method, url, ...args]);
    };

    XMLHttpRequest.prototype.send = function (body) {
        // Check again at send time in case withCredentials was set after open()
        if (this.withCredentials && this._url && !this._url.includes('__credentials=true')) {
            // Reopen with credentials marker
            const hasCredentials = this._url.includes('__credentials=true');
            if (!hasCredentials) {
                const newUrl = this._url + (this._url.includes('?') ? '&' : '?') + '__credentials=true';
                this._url = newUrl;
                originalOpen.call(this, this._method, newUrl, true); // async = true
            }
        }

        if (this._method && ['POST', 'PUT', 'PATCH'].includes(this._method.toUpperCase()) && body) {
            let bodyData;
            let isBase64 = false;
            if (typeof body === 'string') {
                bodyData = body;
            } else if (body instanceof Blob) {
                // Binary data (File, Blob) - convert to base64
                const reader = new FileReader();
                reader.onload = () => {
                    const binary = reader.result;
                    let binaryStr = '';
                    const bytes = new Uint8Array(binary);
                    for (let i = 0; i < bytes.length; i++) {
                        binaryStr += String.fromCharCode(bytes[i]);
                    }
                    bodyData = btoa(binaryStr);
                    isBase64 = true;
                    try {
                        try {
                            this.setRequestHeader('X-Body-Data', bodyData);
                            if (isBase64) this.setRequestHeader('X-Body-Encoding', 'base64');
                        }
                        catch (e) {
                            if (e.name === 'TypeError') {
                                this.setRequestHeader('X-Body-Data', utf8ToBase64(bodyData));
                                this.setRequestHeader('X-Body-Encoding', 'base64');
                            }
                        }
                    } catch (e) {
                        console.error('[IframeInjector] Cannot set X-Body-Data header on XMLHttpRequest', e);
                    }
                    return originalSend.apply(this, arguments);
                };
                reader.readAsArrayBuffer(body);
                return; // Exit to wait for async read
            } else if (body instanceof ArrayBuffer) {
                // ArrayBuffer - convert to base64
                const bytes = new Uint8Array(body);
                let binary = '';
                for (let i = 0; i < bytes.length; i++) {
                    binary += String.fromCharCode(bytes[i]);
                }
                bodyData = btoa(binary);
                isBase64 = true;
            } else if (ArrayBuffer.isView(body)) {
                // Typed arrays (Uint8Array, Int8Array, etc.) - used by protobuffer
                // Convert to base64 to avoid JSON serialization issues
                const bytes = new Uint8Array(body.buffer, body.byteOffset, body.byteLength);
                let binary = '';
                for (let i = 0; i < bytes.length; i++) {
                    binary += String.fromCharCode(bytes[i]);
                }
                bodyData = btoa(binary);
                isBase64 = true;
            } else if (body instanceof FormData) {
                // FormData can't be easily serialized - let browser handle it
                console.warn('[IframeInjector] Skipping body cache for FormData');
                bodyData = null;
            } else if (body instanceof URLSearchParams) {
                // URLSearchParams - convert to string
                bodyData = body.toString();
            } else {
                // Object or other - convert to JSON
                bodyData = JSON.stringify(body);
            }

            if (bodyData) {
                try {
                    try {
                        this.setRequestHeader('X-Body-Data', bodyData);
                        if (isBase64) this.setRequestHeader('X-Body-Encoding', 'base64');
                    }
                    catch (e) {
                        if (e.name === 'TypeError') {
                            this.setRequestHeader('X-Body-Data', utf8ToBase64(bodyData));
                            this.setRequestHeader('X-Body-Encoding', 'base64');
                        }
                    }
                } catch (e) {
                    console.error('[IframeInjector] Cannot set X-Body-Data header on XMLHttpRequest');
                }
            }
        }

        return originalSend.apply(this, arguments);
    };
})();