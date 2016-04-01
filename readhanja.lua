
luatexbase.provides_module({
  name        = 'readhanja',
  date        = '2016/04/01',
  version     = '0.8',
  description = 'Typeset Hanja-to-Hangul sound values',
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
local set_attr      = ndirect.set_attribute
local tailnode      = ndirect.tail
local getlist       = ndirect.getlist
local nodehpack     = ndirect.hpack

local node_id       = node.id
local glyph_id      = node_id("glyph")
local penalty_id    = node_id("penalty")
local rule_id       = node_id("rule")
local kern_id       = node_id("kern")
local hlist_id      = node_id("hlist")
local vlist_id      = node_id("vlist")
local glue_id       = node_id("glue")

local nobreak       = newnode(penalty_id); setfield(nobreak, "penalty", 10000)
local newrule       = newnode(rule_id)
local newkern       = newnode(kern_id, 1)
local hss_glue      = newnode(glue_id)
setfield(hss_glue, "width",         0)
setfield(hss_glue, "stretch",       65536)
setfield(hss_glue, "shrink",        65536)
setfield(hss_glue, "stretch_order", 2)
setfield(hss_glue, "shrink_order",  2)

local fontdata      = fonts.hashes.identifiers
local tohangul      = luatexbase.attributes.readhanjatohangul

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
  for uni in hanja:utfvalues() do
    hanja = uni
  end
  local t = {}
  hanguls = hanguls:gsub(",", "")
  for uni in hanguls:utfvalues() do
    t[#t + 1] = uni
  end
  hanja2hangul[hanja] = t
end
readhanja.add_hanja_reading = add_hanja_reading

local reading_dictionary = {}

-- reading_dictionary 테이블을 추가/수정/삭제한다
-- string * string -> none
local function add_hanja_dictionary (hanjas, hanguls)
  local dict = reading_dictionary
  hanjas = hanjas:gsub("%s","")
  for hanja in hanjas:utfvalues() do
    dict[hanja] = dict[hanja] or {}
    dict = dict[hanja]
  end
  hanguls = hanguls:gsub("%s","")
  if hanguls == "" then
    dict[0] = nil
  else
    dict[0] = {}
    dict = dict[0]
    for hangul in hanguls:utfvalues() do
      dict[#dict + 1] = hangul
    end
  end
end
readhanja.add_hanja_dictionary = add_hanja_dictionary

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

-- 두음법칙에 따라 음가를 바꾸어준다. variation selector가
-- 있는 경우에만 동작한다.
-- number * table * (number | nil) -> number
local function n_dooum_r (hangul, var_seq, last_hangul)
  if last_hangul then -- 단어 중간
    if hangul == 0xB82C or hangul == 0xB960 then -- 렬, 률
      local jong = (last_hangul - 0xAC00) % 28
      if jong == 0 or jong == 4 then -- .모음 or ..ㄴ
        local var_hanja = var_seq[1]
        return hanja2hangul[var_hanja][1]
      end
    end
  else
    if (hangul >= 0xB77C and hangul <= 0xB9C7) then -- ㄹ..
      local var_hanja = var_seq[1]
      return hanja2hangul[var_hanja][1]
    elseif (hangul >= 0xB098 and hangul <= 0xB2E3) then -- ㄴ..
      local hang = hangul + 5292 -- ㅇ..
      for _,v in ipairs(var_seq) do
        if hang == hanja2hangul[v][1] then return hang end
      end
    end
  end
  return hangul
end

-- reading_dictionary 검색해서 다음 노드들의 tohangul 속성을 고치고
-- 첫번째 한자의 한글 음가를 반환한다.
-- table * number * node * table * (node | nil) -> table * number
local function search_dictionary(hanguls, hangul, curr, dict, nn)
  local hanja_nodes = {}
  nn = nn or getnext(curr)
  while nn and getid(nn) == glyph_id do
    local char = getchar(nn)
    if dict[char] then
      hanja_nodes[#hanja_nodes + 1] = nn
      dict = dict[char]
    else
      break
    end
    nn = getnext(nn)
  end
  local readings = dict[0]
  if readings then
    for i,v in ipairs(hanja_nodes) do
      set_attr(v, tohangul, readings[i + 1])
    end
    hangul  = readings[1]
    hanguls = { hangul }
  end
  return hanguls, hangul
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

-- pre_linebreak_filter / hpack_filter callback
-- node -> node
local function read_hanja (head)
  head = todirect(head)
  local curr, start, middle, last_hangul = head, nil, nil, nil
  local typeset = readhanja.locate
  local appends = typeset == "post" and {} or nil
  typeset = readhanja.draft or (typeset ~= "top" and typeset ~= "bottom")

  while curr do
    if getid(curr) == glyph_id then
      local char = getchar(curr)
      if is_var_selector(char) then
        -- pass
      elseif is_hanja_char(char) then
        local o_attr = getattr(curr, tohangul)
        local attr   = (o_attr == 0) and 1 or o_attr
        if attr then

          -- 음가를 결정한다
          local hanguls, hangul
          if attr > 32 then
            hanguls, hangul = {attr}, attr
          else
            local dict = reading_dictionary[char]
            hanguls = hanja2hangul[char]
            hangul  = hanguls and hanguls[attr]
            if o_attr == 0 then
              if hangul then
                local var_seq = hanja2varseq[char]
                if var_seq then
                  local nn = getnext(curr)
                  if nn and getid(nn) == glyph_id then
                    local nn_char   = getchar(nn)
                    local var_hanja = var_seq[ nn_char - 0xFE00 + 1 ]

                    -- variation selector
                    if var_hanja then
                      hangul = hanja2hangul[var_hanja][1]

                    -- 사전 검색
                    elseif dict then
                      hanguls, hangul = search_dictionary(hanguls, hangul, curr, dict, nn)

                    -- 不
                    elseif char == 0x4E0D then
                      local nn_attr    = getattr(nn, tohangul)
                            nn_attr    = (nn_attr == 0) and 1 or nn_attr
                      local nn_hanguls = hanja2hangul[ nn_char ]
                      local syllable   = nn_hanguls and nn_hanguls[nn_attr] or nn_char
                      local cho        = math_floor((syllable - 0xAC00) / 588)
                      hangul = (cho == 3 or cho == 12) and 0xBD80 or 0xBD88 -- ㄷ,ㅈ ? 부 : 불

                    -- 두음법칙
                    elseif not middle then
                      hangul = n_dooum_r(hangul, var_seq)
                    else
                      hangul = n_dooum_r(hangul, var_seq, last_hangul)
                    end
                  elseif not middle then
                    hangul = n_dooum_r(hangul, var_seq)
                  else
                    hangul = n_dooum_r(hangul, var_seq, last_hangul)
                  end

                -- 사전 검색
                elseif dict then
                  hanguls, hangul = search_dictionary(hanguls, hangul, curr, dict)
                end
              elseif dict then
                hanguls, hangul = search_dictionary(hanguls, hangul, curr, dict)
              end
            end
          end

          if typeset then
            local raise = readhanja.raise
            if not raise then
              local fid = getfont(curr)
              raise = fontdata[fid]
              raise = raise and raise.parameters and raise.parameters.x_height
              raise = raise and raise/2 or 0
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
            unset_attr(curr, tohangul)
          else
            set_attr(curr, tohangul, hangul) -- pass to post_linebreak_filter
          end -- end of typeset
          middle, last_hangul = true, hangul
        else
          start, middle, last_hangul = nil, nil, nil
          if appends then
            head, appends = flush_appends(head, curr, appends)
          end
        end -- end of attr
      else
        start, middle, last_hangul = nil, nil, nil
        if appends then
          head, appends = flush_appends(head, curr, appends)
        end
      end -- end of is_hanja_char
    else
      start, middle, last_hangul = nil, nil, nil
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

-- post_linebreak_filter callback
-- node -> node
local function read_hanja_ruby (head, locate)
  local curr = head
  while curr do
    local currid = getid(curr)
    if currid == glyph_id and is_hanja_char(getchar(curr)) then
      local attr = getattr(curr, tohangul)
      if attr then
        local h_glyph   = copynode(curr)
        local currwidth = getfield(h_glyph, "width")        or 655360
        local curr_yoff = getfield(h_glyph, "yoffset")      or 0

        local currfid   = getfont(h_glyph)
        local currfnt   = currfid   and fontdata[currfid]
        local currparam = currfnt   and currfnt.parameters
        local currasc   = currparam and currparam.ascender  or 655360*.8
        local currdesc  = currparam and currparam.descender or 655360/5

        local rubyfid   = readhanja.hangulfont
        local rubyfnt   = rubyfid   and fontdata[rubyfid]
        local rubyparam = rubyfnt   and rubyfnt.parameters
        local rubyasc   = rubyparam and rubyparam.ascender  or  655360*.8
        local rubydesc  = rubyparam and rubyparam.descender or  655360/5

        local ruby_yoff = readhanja.raise or 0
        if locate == "top" then
          ruby_yoff = ruby_yoff + curr_yoff + currasc  + rubydesc
        else
          ruby_yoff = ruby_yoff + curr_yoff - currdesc - rubyasc
        end

        setfield(h_glyph, "font",    rubyfid)
        setfield(h_glyph, "char",    attr)
        setfield(h_glyph, "yoffset", ruby_yoff)

        local l_space = copynode(hss_glue)
        local r_space = copynode(hss_glue)
        setfield(l_space, "next",    h_glyph)
        setfield(h_glyph, "next",    r_space)
        local h_box   = nodehpack(l_space, currwidth, "exactly")
        setfield(h_box,   "width",   0)
        setfield(h_box,   "height",  0)
        setfield(h_box,   "depth",   0)

        head = insert_before(head, curr, h_box)

        unset_attr(curr, tohangul)
      end
    elseif currid == hlist_id or currid == vlist_id then
      local head = getlist(curr)
      head = read_hanja_ruby(head, locate)
      setfield(curr, "head", head)
    end
    curr = getnext(curr)
  end

  return head
end

local add_to_callback       = luatexbase.add_to_callback
local callback_descriptions = luatexbase.callback_descriptions
local remove_from_callback  = luatexbase.remove_from_callback

local function pre_to_callback (name, func, desc)
  local t = { {func, desc} }
  for _,v in ipairs(callback_descriptions(name)) do
    t[#t+1] = {remove_from_callback(name, v)}
  end
  for _,v in ipairs(t) do
    add_to_callback(name, v[1], v[2])
  end
end

pre_to_callback("pre_linebreak_filter", read_hanja, "read_hanja")
pre_to_callback("hpack_filter",         read_hanja, "read_hanja")
add_to_callback("post_linebreak_filter",
                function (head)
                  local locate = readhanja.locate
                  if locate == "top" or locate == "bottom" then
                    head = todirect(head)
                    head = read_hanja_ruby(head, locate)
                    return tonode(head)
                  end
                  return head
                end, "read_hanja")
