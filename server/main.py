
import cherrypy
import json
import re
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
        ss = cherrypy.app['source']
        if ss.get('use') is not None:
            ss = cherrypy.app[ss['use']]
        self._sourceConfig = ss
        t = ss['type'].lower()
        if t == 'lgtask':
            self._source = lgTaskSource.LgTaskSource(ss)
        elif t == 'graphite':
            self._source = graphiteSource.GraphiteSource(ss)
        else:
            raise ValueError("Unknown source type " + t)

        # Do we have storage?
        if 'storage' in cherrypy.app:
            url = cherrypy.app['storage']['dashboards']
            if url.startswith('pymongo://'):
                m = re.match("^pymongo://([^:@]+(:[^@]+)?@)?([^/]+)(:[^/]+)?(/[^/]+)?(/[^/]+)?$", url)
                if m is None:
                    raise ValueError("Invalid pymongo url: " + url)
                user, pwd, host, port, db, coll = m.groups()
                if coll is None:
                    raise ValueError("Storage needs collection")
                # Import so pymongo isn't required; storage is not necessary
                # to run the app
                import pymongo
                self._storage = pymongo.Connection(host = host, port = port,
                        auto_start_request = False)
                # 1: strips leading slash
                self._storage = self._storage[db[1:]][coll[1:]]
            else:
                raise ValueError("Unknown 'dashboards' URL: " + url)
        else:
            self._storage = None


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
    def getStartup(self):
        """Returns a JSON blob about available stats and dashboards
        """
        stats = self._source.getStats()
        return json.dumps({
            'stats': stats
            , 'paths': self._sourceConfig['paths'] 
            , 'dashboards': self._getDashboards()
        })


    @cherrypy.expose
    @cherrypy.config(**{ 'response.headers.Content-Type': 'application/json' })
    def saveDashboard(self, dashDef):
        if self._storage is None:
            return json.dumps(dict(error = "Can't save without storage"))

        dd = json.loads(dashDef)
        if 'id' not in dd:
            raise ValueError("id not found")
        dd['_id'] = dd['id']
        del dd['id']
        self._storage.save(dd)
        return json.dumps(dict(ok = True))


    def _getDashboards(self):
        """Return all dashboards as a list"""
        if self._storage is None:
            return []
        # LOAD EVERYTHING!
        docs = list(self._storage.find())
        for d in docs:
            d['id'] = d['_id']
            del d['_id']
        return docs

