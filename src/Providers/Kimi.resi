// Kimi provider interface — cross-module surface.
let createKimiProvider: unit => Provider.quotaProvider
let buildRequest: string => FetchHttp.httpRequest
let requestOptions: FetchHttp.requestOptions
