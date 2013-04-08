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

        attempt = 0
        while True:
            attempt += 1
            try:
                result = self._request(url, urlParms, keepGzip = True)
                # Flag the response so we know it's encoded right
                cherrypy.response.headers['Content-Encoding'] = 'gzip'
                # This circumvents the gzip tool
                cherrypy.request.cached = True
                return result
            except urllib2.HTTPError, e:
                if int(e.code) == 502 and attempt < 3:
                    continue
                raise


    def getStats(self):
        url = '/metrics/index.json'
        req = self._request(url)
        r = json.loads(req)
        return r


    def _request(self, url, params = None, keepGzip = False):
        """Make a request to graphite using our credentials.

        keepGzip [False] - If True, keep GZIP'd.
        """
        urlBase = self._config['url']
        data = params
        headers = { 'Accept-Encoding': 'gzip,deflate,sdch' }
        if data is not None:
            data = urllib.urlencode(data)
        if self._config.get('authKey') is not None:
            headers['Authorization'] = self._config['authKey']
        req = urllib2.Request(urlBase + url, data = data, headers = headers)
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
    

