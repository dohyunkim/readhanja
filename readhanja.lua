
local err,warn,info,log = luatexbase.provides_module({
  name        = 'readhanja',
  date        = '2015/05/14',
  version     = '0.2',
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
local hanja2varseq  = dofile(kpse.find_file("hanja2varseq.lua"))

-- number -> bool
local function is_var_selector (ch)
  return (ch >= 0xFE00  and ch <= 0xFE0F )
      or (ch >= 0xE0100 and ch <= 0xE01EF)
end

-- number -> bool
local function is_hanja_char (ch)
  return (ch >= 0x4E00  and ch <= 0x9FFF )
      or (ch >= 0x3400  and ch <= 0x4DBF )
      or (ch >= 0x20000 and ch <= 0x2B81F)
      or (ch >= 0xF900  and ch <= 0xFAFF )
      or (ch >= 0x2F800 and ch <= 0x2FA1F)
end

-- string * string -> none
local function add_hanja_reading (hanja, hanguls)
  hanja   = utfbyte(hanja)
  hanguls = hanguls:explode(",")
  for i,v in ipairs(hanguls) do hanguls[i] = utfbyte(v) end
  hanja2hangul[hanja] = hanguls
end
readhanja.add_hanja_reading = add_hanja_reading

-- number * (number | nil) -> node * number
local function get_rule_node (raise, hangul)
  local wd, ht, dp
  local fnt   = fontdata[readhanja.hangulfont]
  local param = fnt and fnt.parameters
  dp = param and param.descender or 655360/5
  if hangul then
    wd = fnt and fnt.characters and fnt.characters[hangul]
    wd = wd  and wd.width or 0
    wd = wd ~= 0 and wd or 655360/2
    ht =  raise - dp
    dp = -raise + dp*2
  else
    wd = param and param.quad or 655360
    ht = param and param.ascender or 655360*.8
    ht = ht + raise
    dp = dp - raise
  end
  local rule = copynode(newrule)
  setfield(rule, "width",  wd)
  setfield(rule, "height", ht)
  setfield(rule, "depth",  dp)
  return rule, wd
end

-- node * node * (number | false) * number * (bool | nil) -> node
local function insert_hangul (head, curr, hangul, raise, allowbreak)
  if hangul then
    local hangulnode  = copynode(curr)
    local yoffset     = getfield(hangulnode, "yoffset") or 0
    setfield(hangulnode, "char", hangul)
    setfield(hangulnode, "font", readhanja.hangulfont)
    setfield(hangulnode, "yoffset", yoffset + raise)
    head = insert_before(head, curr, hangulnode)
  else
    local rule = get_rule_node(raise)
    head = insert_before(head, curr, rule)
  end
  if not allowbreak then
    head = insert_before(head, curr, copynode(nobreak))
  end
  return head
end

-- node -> node
local function read_hanja (head)
  head = todirect(head)
  local curr, start, middle = head, nil, nil
  while curr do
    if getid(curr) == glyph_id then
      local char = getchar(curr)
      if is_var_selector(char) then
        -- pass
      elseif is_hanja_char(char) then
        local fid  = getfont(curr)
        local attr = getattr(curr, tohangul)
        if attr then
          local raise = readhanja.raise
          if not raise then
            raise = fontdata[fid]
            raise = raise and raise.parameters and raise.parameters.x_height
            raise = raise and raise/2 or 0
          end

          local hanguls = hanja2hangul[char]
          local hangul  = hanguls and hanguls[attr]
          if hangul and attr == 1 then
            local var_seq = hanja2varseq[char]
            if var_seq then
              local nn = getnext(curr)
              if nn and getid(nn) == glyph_id then
                local nn_char   = getchar(nn)
                local var_hanja = var_seq[ nn_char - 0xFE00 + 1 ]
                if var_hanja then
                  hangul = hanja2hangul[var_hanja][1]
                elseif char == 0x4E0D then -- 不
                  local nn_attr    = getattr(nn, tohangul)
                  local nn_hanguls = hanja2hangul[ nn_char ]
                  local syllable   = nn_hanguls and nn_hanguls[nn_attr] or nn_char
                  local cho        = math_floor((syllable - 0xAC00) / 588)
                  hangul = (cho == 3 or cho == 12) and 0xBD80 or 0xBD88 -- ㄷ,ㅈ ? 부 : 불
                end
              end
              if middle and hangul >= 0xB098 and hangul <= 0xB2E3 then -- ..ㄴ..
                hangul = hangul + 1764 -- ..ㄹ..
              end
            end
          end

          if readhanja.draft then
            local hanguls = hanguls or { false }
            for i=1,#hanguls do
              local t_hangul = hanguls[i]
              head = insert_hangul(head, curr, t_hangul, raise)
              if #hanguls > 1 and hangul == t_hangul then
                local rule, wd = get_rule_node(raise, hangul)
                local kern     = copynode(newkern)
                setfield(kern, "kern", -wd)
                head = insert_before(head, curr, kern)
                head = insert_before(head, curr, rule)
                head = insert_before(head, curr, copynode(nobreak))
              end
            end

          elseif readhanja.unit == "char" then
            head = insert_hangul(head, curr, hangul, raise)

          else
            start = start or curr
            head  = insert_hangul(head, start, hangul, raise, true)

          end
          middle = true
          unset_attr(curr, tohangul)
        else
          start, middle = nil, nil
        end -- end of attr
      else
        start, middle = nil, nil
      end -- end of is_hanja_char
    else
      start, middle = nil, nil
    end -- end of glyph_id
    curr = getnext(curr)
  end -- end of curr
  return tonode(head)
end

local add_to_callback = luatexbase.add_to_callback
add_to_callback("pre_linebreak_filter", read_hanja, "read_hanja", 1)
add_to_callback("hpack_filter", read_hanja, "read_hanja", 1)
