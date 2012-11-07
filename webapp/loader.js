
//NOTE: This config must be duplicated in app.build.js...
requirejs.config({
    shim: {
        'jquery': {
            deps: [],
            exports: '$'
        }
        ,
        'd3.v2.min': {
            deps: [],
            exports: 'd3'
        }
    }
    , paths: {
        'cs': '../lib/cs',
        'css': '../lib/css',
        'coffee-script': '../lib/coffee-script',
        'jquery': '../lib/jquery-1.8.2.min',
        'lib': '../lib'
    }
});

require(["cs!main"], function() {
    //Just load up main now that we've configured paths
});

