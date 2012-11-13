
class BaseCollection(object):
    """Base collection for storing lamegame_statview data.
    """
    
    def delete(self, id):
        """Removes the data at key id"""
        raise NotImplementedError()
    
    
    def find(self):
        """Returns an iterator of all documents in self."""
        raise NotImplementedError()
        
    
    def save(self, doc):
        """Saves doc in key doc['_id']"""
        raise NotImplementedError()
    