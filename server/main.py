
import cherrypy
import datetime
from flexiInt import FlexiInt
import json
import os
import random
import subprocess
import tempfile
import threading
import time

import graphiteSource
import lgTaskSource

# http://stackoverflow.com/questions/2427240/thread-safe-equivalent-to-pythons-time-strptime
datetime.datetime.strptime("2013-03-18T01:23:45", "%Y-%m-%dT%H:%M:%S")

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

    AUDIT_INTERVAL = 300.0
    AUDIT_INTERVAL_doc = """Every X seconds, clean out old data"""

    lock = threading.RLock()
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
                ('paths', 'path'), ('aliases', 'alias'), ('events', 'event'),
                ('activities', 'activity') ]:
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


    def _addActivity(self, origin, type_, data):
        """Returns the _id of the activity generated, so that clients can ignore
        it."""
        if not self._activityStorage:
            raise Exception("Cannot add activity without storage")

        with self.lock:
            # Clean out old activities, maybe
            self._auditActivities()

            latest = self._activityStorage.get('~latest')
            if latest is None:
                myId = FlexiInt(0).toString()
                latest = { '_id': '~latest' }
            else:
                myId = FlexiInt(FlexiInt(latest['latest']).value + 1).toString()
            latest['latest'] = myId
            self._activityStorage.save(latest)

        self._activityStorage.save({ '_id': myId, 'type': type_, 'data': data,
                'ts': self.tsFormat(datetime.datetime.utcnow()),
                'origin': origin
        })
        return myId


    def _auditActivities(self):
        """Once every AUDIT_INTERVAL, see if there are any old activities and
        clean them out.  Note that we have self.lock when called."""
        old = getattr(self, '_auditActivities_timer', None)
        if old is not None and time.time() - old < self.AUDIT_INTERVAL:
            return
        self._auditActivities_timer = time.time()

        cutoff = datetime.datetime.utcnow() - datetime.timedelta(days = 7)
        toDelete = []
        for d in self._activityStorage.find():
            if '~latest' == d['_id']:
                # Never audit the state placeholder
                continue

            if 'ts' not in d or self.tsRead(d['ts']) <= cutoff:
                toDelete.append(d['_id'])

        for d in toDelete:
            self._activityStorage.delete(d)


    @cherrypy.expose
    def index(self):
        return cherrypy.lib.static.serve_file(_DIR + '/webapp/app.html')


    @cherrypy.expose
    @cherrypy.config(**{ 'response.headers.Content-Type': 'application/json' })
    def addEvent(self, event, origin):
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
        actId = self._addActivity(origin, 'event', eventObject)
        return json.dumps({ "ok": True, "eventId": eventObject['_id'],
                "activityId": actId })
    
    
    @cherrypy.expose
    @cherrypy.config(**{ 'response.headers.Content-Type': 'application/json' })
    def deleteDashboard(self, dashId, origin):
        if self._dashStorage is None:
            return json.dumps(dict(error = "Can't save without storage"))
        
        self._dashStorage.delete(dashId)
        actId = self._addActivity(origin, 'dash.delete', dashId)
        return json.dumps(dict(ok = True, activityId = actId))


    @cherrypy.expose
    @cherrypy.config(**{ 'response.headers.Content-Type': 'application/json' })
    def deletePath(self, pathId):
        if self._pathStorage is None:
            return json.dumps(dict(error = "Can't save without storage"))

        self._pathStorage.delete(pathId)
        return json.dumps(dict(ok = True))


    @cherrypy.expose
    @cherrypy.config(**{ 'response.headers.Content-Type': 'application/json' })
    def getActivities(self, lastId, origin):
        """Returns:
            { lastId: new last id,
              activities: [ list of activities that come after lastId ]"""

        if self._activityStorage is None:
            return json.dumps(dict(error = "Can't get activities! Set up "
                    "storage"))

        # Long-poll
        s = time.time()
        while (time.time() - s < 20.0
                and cherrypy.engine.state != cherrypy.engine.states.STOPPING):
            if (self._activityStorage.get('~latest', {}).get('latest', lastId)
                    != lastId):
                # New activity!  Return that shizzle
                break
            time.sleep(0.1)

        acts = list(self._activityStorage.findRange(lastId, '~'))
        acts = [ a for a in acts if a['_id'] != lastId ]
        acts.sort(key = lambda m: m['_id'])
        newLastId = acts[-1]['_id'] if acts else lastId
        acts = [ a for a in acts if a['origin'] != origin ]
        return json.dumps({ 'lastId': newLastId, 'activities': acts })


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
        latestActivity = self._activityStorage.get('~latest')
        lastActivity = '0' if not latestActivity else latestActivity['latest']
        return json.dumps({
            'stats': stats,
            'paths': self._getPaths(),
            'dashboards': self._getDashboards(),
            'aliases': self._getAliases(),
            'title': self._sourceConfig.get('name', 'LameGame StatView'),
            'lastActivity': lastActivity,
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
        window.location.href = '#HERE_IS_THE_URL_HASH';
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
                    str(cherrypy.app['cherrypy'].get('server.socket_port',
                        8080)) ])).replace("HERE_IS_THE_URL_HASH", q))
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
    def saveDashboard(self, dashDef, origin):
        if self._dashStorage is None:
            return json.dumps(dict(error = "Can't save without storage"))

        dd = json.loads(dashDef)
        if 'id' not in dd:
            raise ValueError("id not found")
        # Save activities with id instead of _id when the type uses it...
        actId = self._addActivity(origin, 'dash', dd)
        dd['_id'] = dd['id']
        del dd['id']
        self._dashStorage.save(dd)
        return json.dumps(dict(ok = True, activityId = actId))


    @cherrypy.expose
    @cherrypy.config(**{ 'response.headers.Content-Type': 'application/json' })
    def saveEvent(self, event, origin):
        if self._eventStorage is None:
            return json.dumps(dict(error = "Can't save without storage"))

        e = json.loads(event)
        if '_id' not in e:
            raise ValueError("_id not found")
        if e.get('delete'):
            self._eventStorage.delete(e['_id'])
            actId = self._addActivity(origin, 'event.delete', e['_id'])
        else:
            self._eventStorage.save(e)
            actId = self._addActivity(origin, 'event', e)
        return json.dumps(dict(ok = True, activityId = actId))


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


    @classmethod
    def tsFormat(cls, d):
        return d.strftime("%Y-%m-%dT%H:%M:%S")


    @classmethod
    def tsRead(cls, d):
        return datetime.datetime.strptime(d, "%Y-%m-%dT%H:%M:%S")


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

