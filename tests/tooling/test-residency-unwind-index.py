"""Two wait observations must retain their function mapping after chunk parsing."""
import csv
import hashlib
import importlib.util
import json
from pathlib import Path
import struct
import sys
import tempfile
from types import SimpleNamespace
import unittest
from unittest.mock import patch

root = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(root / 'build/dependencies/engine-inspection'))
spec = importlib.util.spec_from_file_location('residency', root / 'tools/renderer_probe/read-thread-residency.py')
reader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reader)

class FixturePE:
    FILE_HEADER = SimpleNamespace(Machine=0x8664)
    DIRECTORY_ENTRY_EXCEPTION = [SimpleNamespace(struct=SimpleNamespace(
        BeginAddress=a, EndAddress=b, UnwindData=0x20000+i*4))
        for i, (a,b) in enumerate(((0x1000,0x2000), (0x6f7760,0x6f7800),
                                  (0x6f94d0,0x6f9600), (0x7aa1c0,0x7ad000)))]
    def get_data(self, rva, size):
        if 0x20000 <= rva < 0x20010:
            return bytes([1,0,0,0])[:size]
        return {0x6f7760: bytes.fromhex('4883ec28'),
                0x6f94d9: bytes.fromhex('488bc4415441574883ec78'),
                0x6f953d: b'\xe8'+struct.pack('<i', 0x6f7760-0x6f9542),
                0x7ac4a5: b'\xe8'+struct.pack('<i', 0x6f94d0-0x7ac4aa)}.get(rva,b'')[:size]

class UnwindIndexTests(unittest.TestCase):
    def test_chunk_parse_does_not_change_later_function_owners(self):
        with tempfile.TemporaryDirectory() as tmp:
            directory = Path(tmp)
            binary = directory / 'engine.fixture'
            binary.write_bytes(b'fixture')
            digest = hashlib.sha256(binary.read_bytes()).hexdigest()
            base = 0x140000000
            (directory/'receipt.json').write_text(json.dumps(dict(exit_code=0, pid=123, thread=456,
                game_sha256=digest, observe_dispatch_layout=True)))
            (directory/'modules.json').write_text(json.dumps([dict(name='Darktide.exe', path=str(binary),
                base_address=base, size=0x1000000)]))
            row = dict(qpc='100', rip=hex(base+0x6f77dd), pause_us='50', stack_read='1',
                s5=hex(base+0x6f9542), s23=hex(base+0x7ac4aa), layout_read='1', workers='6',
                commands='10', weighted_commands='10', history_commands='10', weighted_enabled='1',
                history_cost='1', chunks_read='1', chunk_count='1', boundary_count='1', chunk_start0='0')
            with (directory/'samples.csv').open('w', newline='') as output:
                output.write('RESIDENCY_BEGIN pid=123 thread=456 samples=2 requested=2 failure=0 frequency=1000\n')
                writer = csv.DictWriter(output, fieldnames=list(row))
                writer.writeheader()
                writer.writerow(row)
                writer.writerow({**row, 'qpc':'200'})
            with patch.object(reader.pefile, 'PE', return_value=FixturePE()), patch.object(reader, 'KNOWN_ENGINE', digest):
                report = reader.analyze(directory)
            self.assertEqual(report['engine_primary_owners'], {'0x6f7760':2})
            self.assertEqual(report['wait_callers'], [{'call_rva':'0x6f953d','primary_rva':'0x6f94d0','samples':2}])
            self.assertEqual(report['list_wait_parents'], [{'call_rva':'0x7ac4a5','primary_rva':'0x7aa1c0','samples':2}])
            self.assertEqual(report['dispatch_chunks']['samples'], 2)

if __name__ == '__main__': unittest.main()
