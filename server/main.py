
import cherrypy
import json
import os
import random
import re
import subprocess
import tempfile
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
                ('paths', 'path'), ('aliases', 'alias'), ('events', 'event') ]:
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
    def addEvent(self, event):
        """Events should have:
        caption - string, shorthand displayed on mouse over
        content - html text when event is opened
        time - Time, in seconds (including decimal milliseconds) of event.  If
                not supplied, server's now() time will be used.
        """
        if self._eventStorage is None:
            return json.dumps(dict(error = "Can't save without event storage"))

        eventObject = json.loads(event)
        errors = []
        if 'caption' not in eventObject:
            errors.append("Needs caption")
        if 'content' not in eventObject:
            eventObject['content'] = None
        if 'time' not in eventObject:
            eventObject['time'] = time.time()
        if errors:
            return json.dumps(dict(error = ', '.join(errors)))
        # as of 2013-10-31, the seconds column for time is 10 digits long.  It
        # will be 11 digits in 2286.  ...I personally am OK with this for now.
        eventObject['_id'] = "{}-{}".format(str(eventObject['time']),
                random.random())
        self._eventStorage.save(eventObject)
        return json.dumps({ "ok": True, "eventId": eventObject['_id'] })
    
    
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
    def getEvents(self, timeFrom, timeTo):
        """Given timeFrom and timeTo, return (sorted) list of events between the
        two, exclusive on timeTo."""
        if self._eventStorage is None:
            return json.dumps(dict(error = "Can't load events without storage"))

        return json.dumps({ 'events': sorted(self._eventStorage.findRange(
                timeFrom, timeTo), key = lambda m: m['_id']) })


    @cherrypy.expose
    @cherrypy.config(**{ 'response.headers.Content-Type': 'application/json' })
    def getStartup(self):
        """Returns a JSON blob about available stats and dashboards
        """
        cherrypy.response.timeout = 3600
        stats = self._source.getStats()
        return json.dumps({
            'stats': stats,
            'paths': self._getPaths(),
            'dashboards': self._getDashboards(),
            'aliases': self._getAliases(),
            'title': self._sourceConfig.get('name', 'LameGame StatView')
        })


    @cherrypy.expose
    def phantom(self, q):
        """Render an image with phantomjs if it's installed."""
        if os.system("phantomjs --help") != 0:
            return "Phantomjs not installed!"

        # NamedTemporaryFile cleans up after itself
        tf = tempfile.NamedTemporaryFile()
        tf.file.write("""
var page = require('webpage').create();
page.settings.userName = "dev";
page.settings.password = "parola99933";
page.viewportSize = {
    width: 1024,
    height: 768,
};
page.open('http://127.0.0.1:8080/', //'https://lgstats-sellery.sellerengine.com/',
        function() {

    var step1 = null, step2 = null;
    page.evaluate(function() {
        window.location.href = '#{"view":"testdb","timeAmt":"1 day","smoothAmt":"10 minutes","columns":3,"graphHeight":191}';
    });

    function doStep1() {
        var isVis = page.evaluate(function() {
            if (typeof $ === "undefined") {
                return false;
            }
            return $('.dashboard-new').is(':visible');
        });
        if (isVis) {
            clearInterval(step1);
            page.evaluate(function() {
                $('.dashboard-cell.collapsed .dashboard-cell-inner')
                        .click();
            });
            step2 = setInterval(doStep2, 500);

        }
    }
    step1 = setInterval(doStep1, 500);

    function doStep2() {
        var isVis = page.evaluate(function() {
            return $('.load-percent').length === 0;
        });
        if (isVis) {
            console.log(page.renderBase64('png'));
            phantom.exit();
        }
    }
});
            """.replace("127.0.0.1:8080", ":".join([
                    cherrypy.app['cherrypy'].get('server.socket_host',
                        '127.0.0.1'),
                    cherrypy.app['cherrypy'].get('server.socket_port',
                        '8080') ])))
        tf.file.flush()

        sp = subprocess.Popen([ "/usr/bin/phantomjs", tf.name ],
                stdout = subprocess.PIPE)
        stdout, stderr = sp.communicate()

        html = """<html><head><title>Phantom Statview</title></head><body>
            <img src="data:image/png;base64,{}" />
            </body></html>""".format(stdout)

        return html


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
    def saveEvent(self, event):
        if self._eventStorage is None:
            return json.dumps(dict(error = "Can't save without storage"))

        e = json.loads(event)
        if '_id' not in e:
            raise ValueError("_id not found")
        if e.get('delete'):
            self._eventStorage.delete(e['_id'])
        else:
            self._eventStorage.save(e)
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

