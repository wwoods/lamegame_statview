
class LgTaskSource(object):
    def __init__(self, config):
        self._config = config

        import lgTask
        self._conn = lgTask.Connection(self._config['url'])
        self._stats = self._conn.stats

    def getData(self, targetList, timeFrom, timeTo):
        """
        Essentially because it is a really compressed format, we dump like so:
        stat,start,end,interval|data1,data2,data3,data4

        Each stat will be on a new line.

        targetList -- list of stats to get data for
        timeFrom -- epoch seconds (UTC)
        timeTo -- epoch seconds (UTC)
        """
        results = []
        for target in targetList:
            stat = self._stats.getStat(target, timeFrom, timeTo
                , timesAreUtcSeconds = True
            )
            results.append(
                ','.join(
                    [ target, str(stat['tsStart']), str(stat['tsStop'])
                        , str(stat['tsInterval']) ]
                )
                + '|'
                + ','.join([ str(v) for v in stat['values'] ])
            )
        return '\n'.join(results)

    def getStats(self):
        """Return list of all stats"""
        return self._stats.listStats()

