
local err,warn,info,log = luatexbase.provides_module({
  name        = 'readhanja',
  date        = '2015/05/14',
  version     = '0.3',
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
local insert_after  = ndirect.insert_after
local getfield      = ndirect.getfield
local setfield      = ndirect.setfield
local getnext       = ndirect.getnext
local tonode        = ndirect.tonode
local newnode       = ndirect.new
local getattr       = ndirect.has_attribute
local unset_attr    = ndirect.unset_attribute
local tailnode      = ndirect.tail

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

-- hanja2hangul 테이블을 수정/추가한다
-- string * string -> none
local function add_hanja_reading (hanja, hanguls)
  hanja   = utfbyte(hanja)
  hanguls = hanguls:explode(",")
  for i,v in ipairs(hanguls) do hanguls[i] = utfbyte(v) end
  hanja2hangul[hanja] = hanguls
end
readhanja.add_hanja_reading = add_hanja_reading

-- 현재 음가에 밑줄을 긋거나, 음가 결락 한자에 대해 네모상자를
-- 그리는 rule node를 반환한다. `hangul` 변수가 입력된다면
-- 현재 음가에 밑줄긋기 요청임을 의미한다
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

-- 한글 glyph를 추가한다. `pre` 모드에서는 head 노드열에 직접 추가하고,
-- `post` 모드에서는 head 테이블에 추가하여 테이블을 반환한다
-- (node | table) * node * (number | false) * number * bool -> (node | table)
local function insert_hangul (head, curr, hangul, raise, allowbreak)
  local postmode = type(head) == "table"
  if not allowbreak and postmode then
    head[#head + 1] = copynode(nobreak)
  end
  if hangul then
    local hangulnode  = copynode(curr)
    local yoffset     = getfield(hangulnode, "yoffset") or 0
    setfield(hangulnode, "char", hangul)
    setfield(hangulnode, "font", readhanja.hangulfont)
    setfield(hangulnode, "yoffset", yoffset + raise)
    if postmode then
      head[#head + 1] = hangulnode
    else
      head = insert_before(head, curr, hangulnode)
    end
  else
    local rule = get_rule_node(raise)
    if postmode then
      head[#head + 1] = rule
    else
      head = insert_before(head, curr, rule)
    end
  end
  if not allowbreak and not postmode then
      head = insert_before(head, curr, copynode(nobreak))
  end
  return head
end

-- ㄴ이나 ㄹ로 시작하는 음가가 단어 처음에 왔을 때 두음법칙에 따라
-- 음가를 바꾸어준다. 호환한자로의 variation selector를 가지고
-- 있는 한자에 대해서만 이 함수를 호출할 것
-- number * table -> number
local function n_dooum_r (hangul, var_seq)
  if (hangul >= 0xB77C and hangul <= 0xB9C7) then -- ㄹ..
    local var_hanja = var_seq[1]
    return hanja2hangul[var_hanja][1]
  elseif (hangul >= 0xB098 and hangul <= 0xB2E3) then -- ㄴ..
    local hang = hangul + 5292 -- ㅇ..
    for _,v in ipairs(var_seq) do
      if hang == hanja2hangul[v][1] then return hang end
    end
  end
  return hangul
end

-- `post` 모드에서만 필요한 함수. appends 테이블에 들어있는 모든
-- 노드를 노드열에 추가하고 빈 테이블을 반환한다
-- node * node * table * bool -> node * table
local function flush_appends (head, curr, appends, after)
  for _,v in ipairs(appends) do
    if after then
      head, curr = insert_after(head, curr, v)
    else
      head = insert_before(head, curr, v)
    end
  end
  return head, {} -- no need to return curr
end

-- node -> node
local function read_hanja (head)
  head = todirect(head)
  local curr, start, middle = head, nil, nil
  local appends = readhanja.locate == "post" and {} or nil

  while curr do
    if getid(curr) == glyph_id then
      local char = getchar(curr)
      if is_var_selector(char) then
        -- pass
      elseif is_hanja_char(char) then
        local o_attr = getattr(curr, tohangul)
        local attr   = (o_attr == 0) and 1 or o_attr
        if attr then
          local raise = readhanja.raise
          if not raise then
            local fid = getfont(curr)
            raise = fontdata[fid]
            raise = raise and raise.parameters and raise.parameters.x_height
            raise = raise and raise/2 or 0
          end

          -- 음가를 결정한다
          local hanguls = hanja2hangul[char]
          local hangul  = hanguls and hanguls[attr]
          if hangul and o_attr == 0 then
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
                        nn_attr    = (nn_attr == 0) and 1 or nn_attr
                  local nn_hanguls = hanja2hangul[ nn_char ]
                  local syllable   = nn_hanguls and nn_hanguls[nn_attr] or nn_char
                  local cho        = math_floor((syllable - 0xAC00) / 588)
                  hangul = (cho == 3 or cho == 12) and 0xBD80 or 0xBD88 -- ㄷ,ㅈ ? 부 : 불
                elseif not middle then
                  hangul = n_dooum_r(hangul, var_seq)
                end
              elseif not middle then
                hangul = n_dooum_r(hangul, var_seq)
              end
            end
          end

          -- draft 옵션이 주어진 경우
          if readhanja.draft then
            if appends then
              head, appends = flush_appends(head, curr, appends)
            end
            local hanguls = hanguls or { false }
            for i=1,#hanguls do
              local t_hangul = hanguls[i]
              if appends then
                appends = insert_hangul(appends, curr, t_hangul, raise)
              else
                head = insert_hangul(head, curr, t_hangul, raise)
              end
              if #hanguls > 1 and hangul == t_hangul then
                local rule, wd = get_rule_node(raise, hangul)
                local kern     = copynode(newkern)
                setfield(kern, "kern", -wd)
                if appends then
                  appends[#appends + 1] = kern
                  appends[#appends + 1] = rule
                else
                  head = insert_before(head, curr, kern)
                  head = insert_before(head, curr, rule)
                  head = insert_before(head, curr, copynode(nobreak))
                end
              end
            end

          -- 글자 단위로 읽으라고 요구한 경우
          elseif readhanja.unit == "char" then
            if appends then
              head, appends = flush_appends(head, curr, appends)
              appends = insert_hangul(appends, curr, hangul, raise)
            else
              head = insert_hangul(head, curr, hangul, raise)
            end

          -- 디폴트. 단어 단위 처리
          else
            start = start or curr
            if appends then
              appends = insert_hangul(appends, start, hangul, raise, true)
            else
              head  = insert_hangul(head, start, hangul, raise, true)
            end

          end
          middle = true
          unset_attr(curr, tohangul)
        else
          start, middle = nil, nil
          if appends then
            head, appends = flush_appends(head, curr, appends)
          end
        end -- end of attr
      else
        start, middle = nil, nil
        if appends then
          head, appends = flush_appends(head, curr, appends)
        end
      end -- end of is_hanja_char
    else
      start, middle = nil, nil
      if appends then
        head, appends = flush_appends(head, curr, appends)
      end
    end -- end of glyph_id
    curr = getnext(curr)
  end -- end of curr

  if appends then -- 남은 것은 마지막 노드 뒤에다 붙인다
    head = flush_appends(head, tailnode(head), appends, true)
  end
  return tonode(head)
end

local add_to_callback = luatexbase.add_to_callback
add_to_callback("pre_linebreak_filter", read_hanja, "read_hanja", 1)
add_to_callback("hpack_filter", read_hanja, "read_hanja", 1)
