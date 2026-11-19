import lupa.lua51 as l, sys, os
os.chdir(os.path.dirname(os.path.abspath(__file__)))
src = open('harness.lua').read()
L = l.LuaRuntime()
print("== bean counter harness")
total = L.execute(src)
L = l.LuaRuntime()
for f in ['../BeanCounterForever/BeanCounterForever.lua']:
    r = L.eval('function(s) local f, e = loadstring(s) return e or "ok" end')(open(f).read())
    print(f, "syntax:", r)
    if r != "ok": total += 1
sys.exit(1 if total else 0)
