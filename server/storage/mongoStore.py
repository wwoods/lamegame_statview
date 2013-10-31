
import pymongo
import re

from server.storage.base import BaseCollection

class MongoCollection(BaseCollection):
    def __init__(self, url):
        """url to collection, like: pymongo://user:pass@localhost/db/coll
        """
        m = re.match("^pymongo://([^:@]+(:[^@]+)?@)?([^/]+)(:[^/]+)?(/[^/]+)?(/[^/]+)?$", url)
        if m is None:
            raise ValueError("Invalid pymongo url: " + url)
        user, pwd, host, port, db, coll = m.groups()
        if coll is None:
            raise ValueError("Storage needs collection")
        # Import so pymongo isn't required; storage is not necessary
        # to run the app
        import pymongo
        self._conn = pymongo.Connection(host = host, port = port,
                auto_start_request = False)
        # 1: strips leading slash
        self._coll = self._conn[db[1:]][coll[1:]]
        
        
    def delete(self, id):
        self._coll.remove({ '_id': id })
    
        
    def find(self):
        return self._coll.find()


    def findRange(self, a, b):
        """Returns an iterator of all documents between [a, b), exclusive"""
        return self._coll.find({ '_id': { '$gte': a, '$lt': b } })
    
    
    def save(self, doc):
        self._coll.save(doc)
