"""python tools/lighting_v2/call.py PORT proc [args...]: a global proc on the testkit server"""
import os, sys, json
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "testkit"))
import tk
s = tk.load_server(int(sys.argv[1]))
args = [json.loads(a) for a in sys.argv[3:]]
print(sys.argv[2], s.call("call", ref="global", proc=sys.argv[2], args=args))
