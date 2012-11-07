import cherrypy
from StringIO import StringIO
from gzip import GzipFile
import json
import urllib, urllib2

class GraphiteSource(object):
    def __init__(self, config):
        self._config = config


    def getData(self, targetList, timeFrom, timeTo):
        url = '/render'
        urlParms = [
                # OLD : 'aliasSub(aliasByNode(offset(scale(movingAverage(sumSeriesWithWildcards(transformNull(dev.repricing.*.*.*.repricedFreshPercent, 0),3,4),360), -360), 1.0), 2), "^", "% SLA fail dealer ")',
                #('target', 'aliasSub(aliasByNode(sumSeriesWithWildcards(transformNull(dev.repricing.*.*.*.repricedFreshPercent, 0),3,4), 2), "^", "% SLA fail dealer ")'),
                ('format', 'raw'),
                ('from', timeFrom),
                ('until', timeTo),
                ]
        for target in targetList:
            # Graphite takes multiple "target" params for different lines
            urlParms.append(('target', target))
        return self._request(url, urlParms)


    def getStats(self):
        url = '/metrics/index.json'
        r = json.loads(self._request(url, keepGzip = False))
        return r


    def _request(self, url, params = None, keepGzip = True):
        """Make a request to graphite using our credentials.

        keepGzip [True] - If True, keep GZIP'd.
        """
        urlBase = self._config['url']
        data = params
        if data is not None:
            data = urllib.urlencode(data)
        req = urllib2.Request(urlBase + url, data = data,
                headers = { 'Authorization': self._config['authKey'],
                        'Accept-Encoding': 'gzip,deflate,sdch', }
                ) 
        result = urllib2.urlopen(req)
        data = result.read()
        headers = result.headers
        if keepGzip and headers.get('content-encoding') == 'gzip':
            # Don't bother extracting the information, just forward it
            cherrypy.response.headers['Content-Encoding'] = 'gzip'
            cherrypy.response.headers['Content-Type'] = 'text/plain'
        elif not keepGzip and headers.get('content-encoding') == 'gzip':
            # De-gzip!
            data = GzipFile(fileobj = StringIO(data)).read()
        return data
    

