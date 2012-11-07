
import cherrypy
import json
import os
import time

import graphiteSource
import lgTaskSource

_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
_DIR_doc = """Project dir"""

class StaticServer(object):
    """Serve static files from a given root safely.
    """

    def __init__(self, rootDir):
        self._path = rootDir
        if not os.path.isabs(self._path):
            self._path = os.path.abspath(self._path)

    @cherrypy.expose
    def default(self, *args):
        f = os.path.join(self._path, *args)
        return cherrypy.lib.static.serve_file(f)


class MainRoot(object):
    """Example web server root object for development.
    """

    src = StaticServer(_DIR + '/webapp')

    def __init__(self):
        t = cherrypy.app['source']['type'].lower()
        if t == 'lgtask':
            self._source = lgTaskSource.LgTaskSource(cherrypy.app['source'])
        elif t == 'graphite':
            self._source = graphiteSource.GraphiteSource(cherrypy.app['source'])
        else:
            raise ValueError("Unknown source type " + t)


    @cherrypy.expose
    def index(self):
        return cherrypy.lib.static.serve_file(_DIR + '/webapp/app.html')


    @cherrypy.expose
    @cherrypy.config(**{ 'response.headers.Content-Type': 'application/json' })
    def getData(self, targetListJson, timeFrom, timeTo):
        if '.' in timeFrom or '.' in timeTo:
            raise ValueError("timeFrom and timeTo may not have decimals")

        targetList = json.loads(targetListJson)
        timeFrom = int(timeFrom)
        timeTo = int(timeTo)
        r = self._source.getData(targetList, timeFrom, timeTo)
        if cherrypy.response.headers.get('Content-Encoding') == 'gzip':
            # Already encoded
            return r
        return json.dumps(r)


    @cherrypy.expose
    @cherrypy.config(**{ 'response.headers.Content-Type': 'application/json' })
    def getStats(self):
        """Returns a JSON blob about available stats.
        """
        stats = self._source.getStats()
        return json.dumps({
            'stats': stats
            , 'paths': cherrypy.app['source']['paths'] 
        })

