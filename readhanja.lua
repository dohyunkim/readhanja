
local err,warn,info,log = luatexbase.provides_module({
  name        = 'readhanja',
  date        = '2015/05/10',
  version     = '0.1',
  description = 'Hangul reading annotation to Hanja',
  author      = 'Dohyun Kim',
  license     = 'Public Domain',
})

readhanja = readhanja or {}
local readhanja = readhanja

local ndirect       = node.direct
local todirect      = ndirect.todirect
local getid         = ndirect.getid
local getchar       = ndirect.getchar
local getfont       = ndirect.getfont
local copynode      = ndirect.copy
local insert_before = ndirect.insert_before
local getfield      = ndirect.getfield
local setfield      = ndirect.setfield
local getnext       = ndirect.getnext
local tonode        = ndirect.tonode
local newnode       = ndirect.new
local getattr       = ndirect.has_attribute
local unset_attr    = ndirect.unset_attribute

local node_id       = node.id
local glyph_id      = node_id("glyph")
local penalty_id    = node_id("penalty")
local rule_id       = node_id("rule")
local kern_id       = node_id("kern")

local nobreak       = newnode(penalty_id); setfield(nobreak, "penalty", 10000)
local newrule       = newnode(rule_id)
local newkern       = newnode(kern_id, 1)

local fontdata      = fonts.hashes.identifiers
local tohangul      = luatexbase.attributes.readhanjatohangul

local utfbyte       = unicode.utf8.byte
local math_floor    = math.floor

local hanja2hangul  = dofile(kpse.find_file("hanja2hangul.lua"))

-- string * string -> none
local function add_hanja_reading (hanja, hanguls)
  hanja   = utfbyte(hanja)
  hanguls = hanguls:explode(",")
  for i,v in ipairs(hanguls) do hanguls[i] = utfbyte(v) end
  hanja2hangul[hanja] = hanguls
end
readhanja.add_hanja_reading = add_hanja_reading

-- node * node * number * number * (bool | nil) -> node
local function insert_hangul (head, curr, hangul, raise, allowbreak)
    local hangulnode  = copynode(curr)
    local yoffset = getfield(hangulnode, "yoffset") or 0
    setfield(hangulnode, "char", hangul)
    setfield(hangulnode, "font", readhanja.hangulfont)
    setfield(hangulnode, "yoffset", yoffset + raise)
    head = insert_before(head, curr, hangulnode)
    if not allowbreak then
      head = insert_before(head, curr, copynode(nobreak))
    end
    return head
end

-- node * node * table * number * number -> node
local function insert_hangul_draft (head, curr, hanguls, attr, raise)
  for i=1,#hanguls do
    head = insert_hangul(head, curr, hanguls[i], raise)
    if i == attr and #hanguls > 1 then
      local fn = fontdata[readhanja.hangulfont]
      local ch = fn and fn.characters and fn.characters[hanguls[i]]
      local wd = ch and ch.width
      local dp = fn and fn.parameters and fn.parameters.descender
      if not wd or wd == 0 then wd = 655360/2 end
      if not dp or dp == 0 then dp = 655360/6 end
      local kern = copynode(newkern)
      setfield(kern, "kern", -wd)
      local rule = copynode(newrule)
      setfield(rule, "width",  wd)
      setfield(rule, "height", raise-dp)
      setfield(rule, "depth",  2*dp-raise)
      head = insert_before(head, curr, kern)
      head = insert_before(head, curr, rule)
      head = insert_before(head, curr, copynode(nobreak))
    end
  end
  return head
end

-- node -> number
local function special_bul_attr (curr)
  local nn = getnext(curr)
  if nn and getid(nn) == glyph_id then
    local nn_attr = getattr(nn, tohangul)
    if nn_attr then
      local nn_hanguls = hanja2hangul[ getchar(nn) ]
      local syllable = nn_hanguls and nn_hanguls[nn_attr]
      if syllable then
        local cho = math_floor((syllable - 0xAC00) / 588)
        if cho == 3 or cho == 12 then -- ㄷ, ㅈ
          return 1 -- 부
        end
      end
    end
  end
  return 2 -- 불
end

-- node * node * number -> node * node
local function insert_hangul_word (head, curr, raise)
  local start = curr
  while curr and getid(curr) == glyph_id do
    local attr = getattr(curr, tohangul)
    if attr then
      unset_attr(curr, tohangul)
      local char = getchar(curr)
      local hanguls = hanja2hangul[char]
      if hanguls then
        if char == 0x4E0D then attr = special_bul_attr(curr) end -- 不
        head = insert_hangul(head, start, hanguls[attr], raise, true)
      else
        break
      end
    else
      break
    end
    curr = getnext(curr)
  end
  return head, curr
end

-- node -> node
local function read_hanja (head)
  head = todirect(head)
  local curr = head
  while curr do
    if getid(curr) == glyph_id then
      local attr = getattr(curr, tohangul)
      if attr then
        local char = getchar(curr)
        local hanguls = hanja2hangul[char]
        if hanguls then
          local raise = readhanja.raise
          if not raise then
            raise = fontdata[ getfont(curr) ]
            raise = raise and raise.parameters and raise.parameters.x_height
            raise = raise and raise/2 or 0
          end
          if readhanja.draft then
            if char == 0x4E0D then attr = special_bul_attr(curr) end -- 不
            head = insert_hangul_draft(head, curr, hanguls, attr, raise)
          elseif readhanja.unit == "char" then
            if char == 0x4E0D then attr = special_bul_attr(curr) end -- 不
            head = insert_hangul(head, curr, hanguls[attr], raise)
          else
            head, curr = insert_hangul_word(head, curr, raise)
          end
        end
        unset_attr(curr, tohangul)
      end
    end
    curr = getnext(curr)
  end
  return tonode(head)
end

local add_to_callback = luatexbase.add_to_callback
add_to_callback("pre_linebreak_filter", read_hanja, "read_hanja", 1)
add_to_callback("hpack_filter", read_hanja, "read_hanja", 1)
