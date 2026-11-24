-- Drive the libexpat bundled in the kong package through its own luaexpat module (lxp.so links
-- /usr/local/kong/lib/libexpat.so.1). usage: luajit expat.lua <case> [file]; prints one result line.
package.cpath = "/usr/local/lib/lua/5.1/?.so;" .. package.cpath
local lxp = require("lxp")

local delivered = 0
local function parse(doc)
  local p = lxp.new({ CharacterData = function(_, s) delivered = delivered + #s end })
  local ok, err = p:parse(doc)
  if ok then ok, err = p:parse() end
  pcall(p.close, p)  -- lxp raises on close after a failed parse
  return ok and "parsed" or ("rejected: " .. tostring(err))
end

local case = arg[1]
if case == "8176" then
  -- CVE-2024-8176: 100000 nested general entities; recursion in the entity expansion
  local t = { "<!DOCTYPE foo [\n<!ENTITY s0 'deepText'>\n" }
  for i = 1, 100000 do t[#t + 1] = string.format("<!ENTITY s%d '&s%d;'>\n", i, i - 1) end
  t[#t + 1] = "]>\n<foo>&s100000;</foo>\n"
  print(parse(table.concat(t)))
elseif case == "115506" then
  -- CVE-2026-115506: nested-entity amplification; how much text reaches the application first
  local f = assert(io.open(arg[2], "rb")); local doc = f:read("*a"); f:close()
  local r = parse(doc)
  print(r .. " delivered=" .. delivered)
elseif case == "93990" then
  -- CVE-2026-93990: UTF-16LE document with an unpaired high surrogate
  print(parse("\255\254<\0a\0>\0\0\216A\0<\0/\0a\0>\0"))
end
