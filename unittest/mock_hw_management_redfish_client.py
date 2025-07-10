class RedfishClient:
    ERR_CODE_OK = 0
    def __init__(self):
        pass

class BMCAccessor:
    def __init__(self):
        pass
    def login(self):
        return RedfishClient.ERR_CODE_OK
    @property
    def rf_client(self):
        class Dummy:
            def build_get_cmd(self, path): return None
            def exec_curl_cmd(self, cmd): return (RedfishClient.ERR_CODE_OK, '{}', None)
            def build_post_cmd(self, path, data_dict): return None
        return Dummy() 