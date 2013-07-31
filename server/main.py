
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
        for storeType, varShorthand in [ ('dashboards', 'dash'),
                ('paths', 'path'), ('aliases', 'alias') ]:
            store = None
            if cherrypy.app.get('storage', {}).get(storeType) is not None:
                url = cherrypy.app['storage'][storeType]
                if url.startswith('pymongo://'):
                    # Do the import here so pymongo isn't required in places
                    # that are not using it
                    from server.storage.mongoStore import MongoCollection
                    store = MongoCollection(url)
                elif url.startswith('shelve://'):
                    from server.storage.shelveStore import ShelveCollection
                    store = ShelveCollection(url)
                else:
                    raise ValueError("Unknown 'dashboards' URL: " + url)

            varName = '_{0}Storage'.format(varShorthand)
            setattr(self, varName, store)


    @cherrypy.expose
    def index(self):
        return cherrypy.lib.static.serve_file(_DIR + '/webapp/app.html')
    
    
    @cherrypy.expose
    @cherrypy.config(**{ 'response.headers.Content-Type': 'application/json' })
    def deleteDashboard(self, dashId):
        if self._dashStorage is None:
            return json.dumps(dict(error = "Can't save without storage"))
        
        self._dashStorage.delete(dashId)
        return json.dumps(dict(ok = True))


    @cherrypy.expose
    @cherrypy.config(**{ 'response.headers.Content-Type': 'application/json' })
    def deletePath(self, pathId):
        if self._pathStorage is None:
            return json.dumps(dict(error = "Can't save without storage"))

        self._pathStorage.delete(pathId)
        return json.dumps(dict(ok = True))


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
            'stats': stats,
            'paths': self._getPaths(),
            'dashboards': self._getDashboards(),
            'aliases': self._getAliases(),
            'title': self._sourceConfig.get('name', 'LameGame StatView')
        })


    @cherrypy.expose
    @cherrypy.config(**{ 'response.headers.Content-Type': 'application/json' })
    def saveAlias(self, groupDef):
        if self._aliasStorage is None:
            return json.dumps(dict(error = "Can't save without storage"))

        dd = json.loads(groupDef)
        dd['_id'] = dd.pop('id')
        if dd['aliases']:
            self._aliasStorage.save(dd)
        else:
            self._aliasStorage.delete(dd['_id'])
        return json.dumps(dict(ok = True))


    @cherrypy.expose
    @cherrypy.config(**{ 'response.headers.Content-Type': 'application/json' })
    def saveDashboard(self, dashDef):
        if self._dashStorage is None:
            return json.dumps(dict(error = "Can't save without storage"))

        dd = json.loads(dashDef)
        if 'id' not in dd:
            raise ValueError("id not found")
        dd['_id'] = dd['id']
        del dd['id']
        self._dashStorage.save(dd)
        return json.dumps(dict(ok = True))


    @cherrypy.expose
    @cherrypy.config(**{ 'response.headers.Content-Type': 'application/json' })
    def savePath(self, pathDef):
        if self._pathStorage is None:
            return json.dumps(dict(error = "Can't save without storage"))

        dd = json.loads(pathDef)
        if 'id' not in dd:
            raise ValueError("id not found")
        dd['_id'] = dd['id']
        del dd['id']
        self._pathStorage.save(dd)
        return json.dumps(dict(ok = True))


    @cherrypy.expose
    @cherrypy.config(**{ 'response.headers.Content-Type': 'application/json' })
    def setAliases(self, aliases):
        if self._aliasStorage is None:
            return json.dumps(dict(error = "Can't save without storage"))

        aliases = json.loads(aliases)
        for k, v in aliases.iteritems():
            dd = dict(_id = k, aliases = v)
            self._aliasStorage.save(dd)

        return json.dumps(dict(ok = True))


    def _getAliases(self):
        """Return all aliases as [ { id: group, aliases: { from: to } } ]
        """
        if self._aliasStorage is None:
            return {}
        docs = list(self._aliasStorage.find())
        for d in docs:
            d['id'] = d.pop('_id')
        return docs


    def _getDashboards(self):
        """Return all dashboards as a list"""
        if self._dashStorage is None:
            return []
        # LOAD EVERYTHING!
        docs = list(self._dashStorage.find())
        for d in docs:
            d['id'] = d['_id']
            del d['_id']
        return docs


    def _getPaths(self):
        """Return all paths as a list"""
        if self._pathStorage is None:
            return self._sourceConfig.get('paths', [])

        docs = list(self._pathStorage.find())
        for d in docs:
            d['id'] = d['_id']
            del d['_id']
        return docs

