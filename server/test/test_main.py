
# Importing run adds cherrypy overrides
from util import Config
from server.main import MainRoot

import cherrypy
import datetime
import os
import unittest

class TestMain(unittest.TestCase):
    APP_INI = os.path.join(os.path.dirname(__file__), '../../app.ini')

    def test_auditActivities(self):
        config = Config()
        config.merge(self.APP_INI)
        config["source"] = dict(type = "graphite")

        cherrypy.app = config
        mr = MainRoot()

        a = mr._activityStorage
        for d in a.find():
            a.delete(d['_id'])

        now = datetime.datetime.utcnow()
        then = now - datetime.timedelta(days = 7.1)
        a.save({ '_id': '10', 'ts': mr.tsFormat(then) })
        a.save({ '_id': '11', 'ts': mr.tsFormat(now) })

        mr._auditActivities()
        remaining = list(a.find())
        self.assertEqual(1, len(remaining))
        self.assertEqual('11', remaining[0]['_id'])

        # Add another and make sure audit doesn't happen because delay hasn't
        # occurred yet.

        a.save({ '_id': '12', 'ts': mr.tsFormat(then) })
        mr._auditActivities()
        remaining = list(a.find())
        self.assertEqual(2, len(remaining))

        mr.AUDIT_INTERVAL = 0.0
        mr._auditActivities()
        remaining = list(a.find())
        self.assertEqual(1, len(remaining))
