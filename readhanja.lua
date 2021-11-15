
luatexbase.provides_module({
  name        = 'readhanja',
  date        = '2021/04/01',
  version     = '0.9',
  description = 'Typeset Hanja-to-Hangul sound values',
  author      = 'Dohyun Kim',
  license     = 'Public Domain',
})

readhanja = readhanja or {}
local readhanja = readhanja

local copynode      = node.copy
local insert_before = node.insert_before
local insert_after  = node.insert_after
local getnext       = node.getnext
local newnode       = node.new
local get_attr      = node.has_attribute
local unset_attr    = node.unset_attribute
local set_attr      = node.set_attribute
local tailnode      = node.tail
local setglue       = node.setglue

local glyph_id      = node.id"glyph"
local penalty_id    = node.id"penalty"
local rule_id       = node.id"rule"
local kern_id       = node.id"kern"
local glue_id       = node.id"glue"

local nobreak       = newnode(penalty_id); nobreak.penalty = 10000
local newrule       = newnode(rule_id)
local newkern       = newnode(kern_id, 0)
local hss_glue      = newnode(glue_id); setglue(hss_glue, 0, 65536, 65536, 2, 2)

local tohangul      = luatexbase.attributes.readhanjatohangul
local yoff_attr     = luatexbase.new_attribute"readhanja_yoffset"

local hanja2hangul  = require "hanja2hangul.lua"
local hanja2varseq  = require "hanja2varseq.lua"

-- number -> bool
local function is_var_selector (ch)
  return ch >= 0xFE00  and ch <= 0xFE0F
      or ch >= 0xE0100 and ch <= 0xE01EF
end

-- number -> bool
local function is_hanja_char (ch)
  return ch >= 0x4E00  and ch <= 0x9FFF
      or ch >= 0x3400  and ch <= 0x4DBF
      or ch >= 0x20000 and ch <= 0x2B81F
      or ch >= 0xF900  and ch <= 0xFAFF
      or ch >= 0x2F800 and ch <= 0x2FA1F
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

local harfbuzz = luaotfload.harfbuzz
local os2tag = harfbuzz and harfbuzz.Tag.new"OS/2"

local fonts_asc_desc = setmetatable( {}, { __index = function(t, fid)
    if fid then
      local fd = font.getfont(fid)
      local asc, desc = fd.parameters.ascender, fd.parameters.descender
      if not asc or not desc then
        local hb = fd.hb
        if hb and os2tag then
          local hbface = hb.shared.face
          local tags = hbface:get_table_tags()
          local hasos2 = false
          for _,v in ipairs(tags) do
            if v == os2tag then
              hasos2 = true
              break
            end
          end
          if hasos2 then
            local os2 = hbface:get_table(os2tag)
            local length = os2:get_length()
            if length > 69 then -- sTypoAscender (int16)
              local data = os2:get_data()
              local typoascender  = string.unpack(">h", data, 69)
              local typodescender = string.unpack(">h", data, 71)
              asc  =  typoascender  * hb.scale
              desc = -typodescender * hb.scale
            end
          end
        end
      end
      if not asc or not desc then
        asc, desc = fd.size*.8, fd.size*.2
      end
      t[fid] = { asc, desc }
      return { asc, desc }
    end
    return { }
  end } )

-- 현재 음가에 밑줄을 긋거나, 음가 결락 한자에 대해 네모상자를
-- 그리는 rule node를 반환한다. `hangul` 변수가 입력된다면
-- 현재 음가에 밑줄긋기 요청임을 의미한다
-- number * (number | nil) -> node * number
local function get_rule_node (raise, hangul)
  local wd, ht, dp
  local fid = readhanja.hangulfont
  local fnt = font.getfont(fid)
  local asc, desc = table.unpack(fonts_asc_desc[fid])
  if hangul then
    wd = fnt and fnt.characters and fnt.characters[hangul]
    wd = wd  and wd.width or 0
    wd = wd ~= 0 and wd or fnt.size/2
    ht = raise  - desc
    dp = desc*2 - raise
  else
    wd = fnt.size
    ht = asc  + raise
    dp = desc - raise
  end
  local rule = copynode(newrule)
  rule.width  = wd
  rule.height = ht
  rule.depth  = dp
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
    hangulnode.char = hangul
    hangulnode.font = readhanja.hangulfont
    raise = tex.sp(raise) -- integer only
    if raise ~= 0 then
      set_attr(hangulnode, yoff_attr, raise)
    end
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
    if hangul >= 0xB77C and hangul <= 0xB9C7 then -- ㄹ..
      local var_hanja = var_seq[1]
      return hanja2hangul[var_hanja][1]
    elseif hangul >= 0xB098 and hangul <= 0xB2E3 then -- ㄴ..
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
  while nn and nn.id == glyph_id do
    local char = nn.char
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
  local curr, start, middle, last_hangul = head
  local typeset = readhanja.locate
  local appends = typeset == "post" and {}
  typeset = readhanja.draft or (typeset ~= "top" and typeset ~= "bottom")

  while curr do
    if curr.id == glyph_id then
      local char = curr.char
      if is_var_selector(char) then
        -- pass
      elseif is_hanja_char(char) then
        local o_attr = get_attr(curr, tohangul)
        local attr   = o_attr == 0 and 1 or o_attr
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
                  if nn and nn.id == glyph_id then
                    local nn_char   = nn.char
                    local var_hanja = var_seq[ nn_char - 0xFE00 + 1 ]

                    -- variation selector
                    if var_hanja then
                      hangul = hanja2hangul[var_hanja][1]

                    -- 사전 검색
                    elseif dict then
                      hanguls, hangul = search_dictionary(hanguls, hangul, curr, dict, nn)

                    -- 不
                    elseif char == 0x4E0D then
                      local nn_attr    = get_attr(nn, tohangul)
                            nn_attr    = nn_attr == 0 and 1 or nn_attr
                      local nn_hanguls = hanja2hangul[ nn_char ]
                      local syllable   = nn_hanguls and nn_hanguls[nn_attr] or nn_char
                      local cho        = (syllable - 0xAC00) // 588
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
              raise = font.getparameters(curr.font).x_height / 2
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
                  kern.kern = -wd
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
  return head
end

-- post_linebreak_filter callback
-- node -> node
local function read_hanja_ruby (head, locate)
  local curr = head
  while curr do
    if curr.id == glyph_id then
      local attr = get_attr(curr, tohangul)
      if attr and attr ~= 0 then
        local h_glyph   = copynode(curr)
        local currwidth = h_glyph.width   or 655360
        local curr_yoff = h_glyph.yoffset or 0

        local currfid  = h_glyph.font
        local currasc, currdesc = table.unpack(fonts_asc_desc[currfid])

        local rubyfid  = readhanja.hangulfont
        local rubyasc, rubydesc = table.unpack(fonts_asc_desc[rubyfid])

        local ruby_yoff = readhanja.raise or 0
        if locate == "top" then
          ruby_yoff = ruby_yoff + curr_yoff + currasc  + rubydesc
        else
          ruby_yoff = ruby_yoff + curr_yoff - currdesc - rubyasc
        end

        h_glyph.font    = rubyfid
        h_glyph.char    = attr
        h_glyph.yoffset = ruby_yoff

        local rb_wd = h_glyph.width
        local leftsp = (currwidth - rb_wd)/2
        local k = copynode(newkern)
        k.kern = leftsp
        local k2 = copynode(k)
        k2.kern = -leftsp-rb_wd
        head = insert_before(head, curr, k)
        head = insert_before(head, curr, h_glyph)
        head = insert_before(head, curr, k2)

        unset_attr(curr, tohangul)
      end
    end
    curr = getnext(curr)
  end

  return head
end

local function post_shaping_raise (head)
  local curr = head
  while curr do
    if curr.id == glyph_id then
      local attr = get_attr(curr, yoff_attr)
      if attr then
        local yoff = attr + (curr.yoffset or 0)
        curr.yoffset = yoff
      end
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

pre_to_callback("pre_shaping_filter", read_hanja, "read_hanja.pre_post")
add_to_callback("post_shaping_filter",
                function (head)
                  local locate = readhanja.locate
                  if locate == "top" or locate == "bottom" then
                    head = read_hanja_ruby(head, locate)
                  elseif locate == "pre" or locate == "post" then
                    head = post_shaping_raise(head)
                  end
                  return head
                end, "read_hanja.top_bottom")
