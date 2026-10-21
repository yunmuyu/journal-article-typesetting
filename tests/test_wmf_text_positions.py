import importlib.util
import struct
from pathlib import Path
spec=importlib.util.spec_from_file_location('wmf_positions',Path(__file__).parent.parent/'2-导入_InDesign/normalize_wmf_text_positions.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
def rec(function,payload):return struct.pack('<IH',3+len(payload)//2,function)+payload
body=rec(0x12e,struct.pack('<H',25))+rec(0x214,struct.pack('<hh',878,4920))+rec(0xa32,struct.pack('<hhHH',0,0,2,0)+b'\xa1\xdc'+struct.pack('<hh',415,0))+rec(0xa32,struct.pack('<hhHH',0,0,2,0)+b'\xa1\xdc'+struct.pack('<hh',672,0))+rec(0,b'')
header=struct.pack('<HHHIHIH',1,9,0x300,(18+len(body))//2,2,10,0)
source=header+body
normalized,inserted=module.normalize(source)
assert inserted==1
assert rec(0x214,struct.pack('<hh',878,5335)) in normalized
assert struct.unpack_from('<I',normalized,6)[0]*2==len(normalized)
assert module.normalize(normalized)==(normalized,0)
assert source==header+body
print('PASS continuous WMF comparison positions, valid header, idempotence and source preservation')
