import sys, os, subprocess
os.chdir(os.path.dirname(os.path.abspath(__file__)))
# Runs the mock harness with Lua 5.1: lupa if installed, else the lua5.1 binary.
FILES = ['../NeedfulSlots/NeedfulSlots.lua']
total = 0
print("== needful slots harness")
try:
    import lupa.lua51 as l
    total = l.LuaRuntime().execute(open('harness.lua').read())
    L = l.LuaRuntime()
    check = L.eval('function(s) local f, e = loadstring(s) return e or "ok" end')
    for f in FILES:
        r = check(open(f).read()); print(f, "syntax:", r)
        if r != "ok": total += 1
except ImportError:
    r = subprocess.run(['lua5.1', '-e', 'local f = assert(loadfile("harness.lua")) os.exit(f() == 0 and 0 or 1)'])
    total += r.returncode
    for f in FILES:
        r = subprocess.run(['luac5.1' if os.path.exists('/usr/bin/luac5.1') else 'luac', '-p', f])
        print(f, "syntax:", "ok" if r.returncode == 0 else "ERROR"); total += r.returncode
# Bindings.xml must be well-formed XML
import xml.etree.ElementTree as ET
try:
    root = ET.parse('../NeedfulSlots/Bindings.xml').getroot()
    print("Bindings.xml: well-formed,", len(root), "bindings")
except Exception as e:
    print("Bindings.xml: XML ERROR", e); total += 1
sys.exit(1 if total else 0)
