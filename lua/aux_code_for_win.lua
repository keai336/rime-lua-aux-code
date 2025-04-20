local AuxFilter = {}
-- 定义记忆词典路径   用辅码选词用户词典没有记忆,只能在这里统计,然后后续处理.不知道怎么直接操作用户词典
local logFilePath = rime_api.get_user_data_dir() .. "/dic.log"
-- 打开文件以追加模式写入
local dicfile = io.open(logFilePath, "a")
local function logdic(message)
    if dicfile then
    -- 获取当前时间
    local time = os.date("%Y-%m-%d %H:%M:%S")
    -- 格式化日志信息
    local logMessage = string.format("[%s] %s\n", time, message)
    -- 写入日志文件
    dicfile:write(logMessage)
    -- 刷新缓冲区
    dicfile:flush()
else
    log.info("无法打开日志文件")
end
end  
-- 获取表的字符串形式
local function str_table(tbl)
    local lines = {}
    for k, v in pairs(tbl) do
        table.insert(lines, tostring(k) .. "=" .. tostring(v))
    end
    return table.concat(lines, "\n")
end
-- 获取表的长度 判断表是不是空表
function table.size(t)
    local s = 0;
    for k, v in pairs(t) do
        if v ~= nil then s = s + 1 end
        end
   return s
end
-- 定义函数来统计子字符串出现的次数
local function countSubstringOccurrences(str, substr)
    local count = 0
    local startPos = 1

    while true do
        local foundPos = string.find(str, substr, startPos, true) -- true 表示按字面意义查找（不使用模式匹配）
        if not foundPos then
            break
        end
        count = count + 1
        startPos = foundPos + #substr -- 更新开始位置以继续查找
    end

    return count
end

-- 计算UTF-8字符串中的字符数量
local function utf8len(str)
    local len = 0
    local currentIndex = 1
    local bytes = string.len(str)
    while currentIndex <= bytes do
        len = len + 1
        local byte = string.byte(str, currentIndex)
        if byte <= 127 then
            currentIndex = currentIndex + 1
        elseif byte <= 223 then
            currentIndex = currentIndex + 2
        elseif byte <= 239 then
            currentIndex = currentIndex + 3
        else
            currentIndex = currentIndex + 4
        end
    end
    return len
end

-- 提取UTF-8字符串的子字符串
local function utf8sub(str, i, j)
    local currentIndex = 1
    local startIndex = 1
    local endIndex = string.len(str)

    local function nextIndex(currentIndex)
        local byte = string.byte(str, currentIndex)
        if byte <= 127 then
            return currentIndex + 1
        elseif byte <= 223 then
            return currentIndex + 2
        elseif byte <= 239 then
            return currentIndex + 3
        else
            return currentIndex + 4
        end
    end

    local len = utf8len(str)
    if i < 0 then
        i = len + i + 1
    end
    if j == nil then
        j = len
    elseif j < 0 then
        j = len + j + 1
    end

    local charIndex = 1
    while currentIndex <= string.len(str) do
        if charIndex == i then
            startIndex = currentIndex
        end
        if charIndex == j + 1 then
            endIndex = currentIndex - 1
            break
        end
        currentIndex = nextIndex(currentIndex)
        charIndex = charIndex + 1
    end

    return string.sub(str, startIndex, endIndex)
end
function AuxFilter.init(env)
    local engine = env.engine
    AuxFilter.memory = Memory(env.engine, env.engine.schema)
    local defaultuserprefer = {path="ZRM_Aux-code",showor="true",trigger=";",matchmode="s"}
    local keys = {"path", "showor","trigger", "matchmode"}
    local userprefer = string.gmatch(env.name_space,"([^@]+)") or ""
    local counter0 = 0
    for item in userprefer do
        counter0 = counter0+1
        -- log.info(item)
        if item then
            if keys[counter0] == nil then
                break
            end
            defaultuserprefer[keys[counter0]] = item
        end
    end
    -- log.info(defaultuserprefer)
     --设置匹配模式 0宽松匹配和1严格匹配  默认严格 l为宽松
    if defaultuserprefer["matchmode"] == "s" then
        AuxFilter.matchmode=1
    else
        AuxFilter.matchmode = 0
    end
        -- if AuxFilter.comb_code == nil then
    --     AuxFilter.comb_code = AuxFilter.read_ybxkcomb_File("ybxkcomb")
    -- end
    -- 設定預設觸發鍵為分號，並從配置中讀取自訂的觸發鍵
    AuxFilter.trigger_key = defaultuserprefer["trigger"]
    AuxFilter.trigger_key_pattern = AuxFilter.trigger_key:gsub("%W", "%%%1") -- 處理特殊字符  --正则中应该表现的形式。
    -- 设定是否显示辅助码，默认为显示
    AuxFilter.show_aux_notice = defaultuserprefer["showor"]
    if AuxFilter.show_aux_notice == "false" then
        AuxFilter.show_aux_notice = false
    else
        AuxFilter.show_aux_notice = true
    end
    logdic("基礎配置加載成功")
    -- hook  preedit_format
    local preedit_config = env.engine.schema.config:get_list("translator/preedit_format1")
    -- logdic(str_table(preedit_config))
    if preedit_config~=nil then
        logdic("preedit_config")
        AuxFilter.preedit_trans = Projection()
        logdic("load")
        AuxFilter.preedit_trans:load(preedit_config)
        logdic("load 成功")
    else 
        AuxFilter.preedit_trans = nil
    end
    logdic("hook 成功")
    if AuxFilter.aux_code == nil then
        AuxFilter.readAuxTxt(defaultuserprefer["path"])
        logdic("readAuxTxt 成功")
    end
    -- 加載輔助碼文件
    -- 不同模式不同处理逻辑

    env.notifier = engine.context.select_notifier:connect(function(ctx)

    if env.notifiermark ==1 then
        AuxFilter.main1_notifier(ctx)
    elseif env.notifiermark==2 then
        AuxFilter.longcandimodify_notifier(ctx)
    elseif env.notifiermark==3 then
        AuxFilter.longcandimodify_ybnotifier(ctx)
    elseif env.notifiermark==4 then
        AuxFilter.singlechar_notifier(ctx)
    end
    -- local lastcommit = ctx.commit_history:back()
    -- if lastcommit ~= "" then
        
    -- logdic("text:" .. lastcommit.text)
    -- logdic("type: " .. lastcommit.type)
    -- end
    end)
end
--- notifier main1模式  (辅筛)
    ----------------------------
    -- 持續選詞上屏，保持輔助碼分隔符存在 --
    ----------------------------
function AuxFilter.main1_notifier(ctx)
    -- local preedit = ctx:get_preedit()
    --     local removeAuxInput = ctx.input:match("([^,]+)" .. AuxFilter.trigger_key_pattern)
    --     local reeditTextFront = preedit.text:match("([^,]+)" .. AuxFilter.trigger_key_pattern)
        -- log.info(removeAuxInput,reeditTextFront)
        -- ctx.text 隨著選字的進行，oaoaoa； 有如下的輸出：
        -- ---- 有輔助碼 ----
        -- >>> 啊 oaoa；au
        -- >>> 啊吖 oa；au
        -- >>> 啊吖啊；au
        -- ---- 無輔助碼 ----
        -- >>> 啊 oaoa；
        -- >>> 啊吖 oa；
        -- >>> 啊吖啊；
        -- 這邊把已經上屏的字段 (preedit:text) 進行分割；
        -- 如果已經全部選完了，分割後的結果就是 nil，否則都是 吖卡 a 這種字符串
        -- 驗證方式：
        -- log.info('select_notifier', ctx.input, removeAuxInput, preedit.text, reeditTextFront)

        -- 當最終不含有任何字母時 (候選)，就跳出分割模式，並把輔助碼分隔符刪掉
        AuxFilter.Update_codes(ctx)
        ctx.input = AuxFilter.removeAuxInput
        if AuxFilter.removetransdInput ~= "" then

            -- 給詞尾自動添加分隔符，上面的 re.match 會把分隔符刪掉
            ctx.input = ctx.input .. AuxFilter.trigger_key
        else
            -- 剩下的直接上屏
            ctx:commit()
        end
    end







--- notifier longcandimodify模式  (断句模式)
    ----------------------------
    -- 保持輔助碼分隔符和原辅码存在 --
    ----------------------------
function AuxFilter.longcandimodify_notifier(ctx)
    local preedit = ctx:get_preedit()
        local removeAuxInput = ctx.input:match("(%a*)" .. AuxFilter.trigger_key_pattern.."-")
        local auxcode = ctx.input:match(AuxFilter.trigger_key_pattern.. "(%a*)" .. AuxFilter.trigger_key_pattern)
        -- log.info("auxcode",auxcode)
        -- log.info("removeauxinput",removeAuxInput)
        local reeditTextFront = preedit.text:match("([^"..AuxFilter.trigger_key_pattern .."]-)" .. AuxFilter.trigger_key_pattern)
        ctx.input = removeAuxInput
        if reeditTextFront and reeditTextFront:match("[a-z]") then
            -- 給詞尾自動添加分隔符和原辅码进入到辅筛模式，上面的 re.match 會把分隔符刪掉
            ctx.input = ctx.input .. AuxFilter.trigger_key .. auxcode
        else
            -- 剩下的直接上屏 
            ctx:commit()
            
        end
    end

--- notifier longcandimodify2模式(修音模式) 
function AuxFilter.longcandimodify_ybnotifier(ctx)
    -- log.info("modifyinput",AuxFilter.ybmodifiedcode)
    ctx.input = AuxFilter.ybmodifiedcode
    end
---  notifier singlechar_notifier(连续单字模式)
function AuxFilter.singlechar_notifier(ctx)
     -- log.info("modifyinput",AuxFilter.ybmodifiedcode)
    ctx.input = AuxFilter.trigger_key
    end
       


-- 生成所有长度为1和2的组合 的函数  输入 adf 会输出 {a,d,f,ad,af,df}  
local function two_char_combinations(str)
    local result = {}
    local n = #str
    
    -- 生成所有长度为1的组合
    for i = 1, n do
        table.insert(result, str:sub(i, i))
    end
    
    -- 生成所有长度为2的组合
    for i = 1, n do
        for j = i + 1, n do
            table.insert(result, str:sub(i, i) .. str:sub(j, j))
        end    
    end
    
    return result
end

----------------
----------------
-- 閱讀輔碼文件 --
----------------
function AuxFilter.readAuxTxt(txtpath)
    -- 读得文件格式变了 字 音 辅的表   ||  嗄	aa	kw
    -- log.info("** AuxCode filter", 'read Aux code txt:', txtpath)
    -- log.info("读文件") --这里打印日志 
    local defaultFile = 'ZRM_Aux-code_4.3.txt'
    local userPath = rime_api.get_user_data_dir() .. "/lua/"
    local fileAbsolutePath = userPath .. txtpath .. ".txt"
    -- log.info(fileAbsolutePath)
    -- 启动本地服务
    local file = io.open(fileAbsolutePath, "r") or io.open(userPath .. defaultFile, "r")
    if not file then
        error("Unable to open auxiliary code file.")
        return {}
    end
    local zi_to_yin_set = {}   -- 字 -> set：{[音码] = true}
    local auxCodesSet = {}     -- 字 -> set：{[辅码] = true}
    local mixedCodes = {}      -- 音码 -> 辅码 -> {字 set}
    
    for line in file:lines() do
        line = line:match("[^\r\n]+")  -- 去除换行符
        local zi, fu, yb = string.match(line, "^([^\t]+)\t([^\t]+)\t?([^\t]*)$")
        if zi and yb and fu then
            local fuset = two_char_combinations(fu)
    
            -- 1. 去重插入 auxCodesSet
            auxCodesSet[zi] = auxCodesSet[zi] or {}
            auxCodesSet[zi][fu] = true
    
            -- 2. 去重插入 zi_to_yin_set
            zi_to_yin_set[zi] = zi_to_yin_set[zi] or {}
            zi_to_yin_set[zi][yb] = true
    
            -- 3. mixedCodes 构建为 set
            if yb ~= "" then
                mixedCodes[yb] = mixedCodes[yb] or {}
                for _, comb in ipairs(fuset) do
                    mixedCodes[yb][comb] = mixedCodes[yb][comb] or {}
                    mixedCodes[yb][comb][zi] = true
                end
            end
        end
    end
    
    -- 将 set 转换为数组形式（后处理）
    
    -- auxCodes: 字 -> {辅码列表}
    local auxCodes = {}
    for zi, fu_set in pairs(auxCodesSet) do
        auxCodes[zi] = {}
        for fu in pairs(fu_set) do
            table.insert(auxCodes[zi], fu)
        end
    end
    
    -- zi_to_yin: 字 -> {音码列表}
    local zi_to_yin = {}
    for zi, yin_set in pairs(zi_to_yin_set) do
        zi_to_yin[zi] = {}
        for yb in pairs(yin_set) do
            table.insert(zi_to_yin[zi], yb)
        end
    end
    
    -- mixedCodes: 音码 -> 辅码 -> {字列表}
    for yb, fus in pairs(mixedCodes) do
        for fu, zi_set in pairs(fus) do
            local zi_list = {}
            for zi in pairs(zi_set) do
                table.insert(zi_list, zi)
            end
            mixedCodes[yb][fu] = zi_list
        end
    end
    
    -- 最终赋值
    AuxFilter.aux_code = auxCodes
    AuxFilter.comb_code = mixedCodes
    AuxFilter.zi_to_yin = zi_to_yin
    AuxFilter.longcandimodify_flag = true
    if table.size(AuxFilter.comb_code) == 0 then
        AuxFilter.longcandimodify_flag = false
        logdic("🈚️音碼配置")
    end
    file:close()
    return auxCodes
end

-----------------------------------------------
-- 計算詞語整體的輔助碼
-- 目前定義為
--   把字或词组的所有辅码，第一个键堆到一起，第二个键堆到一起
--   例子：
--       候选(word) = 拜日
--          【拜】 的辅码有 charAuxCodes=
--             p a
--             p u
--             u a
--             u f
--             u u
--          【日】 的辅码有 charAuxCodes=
--             o r
--             r i
--             a a
--             u h
--       (竖着拍成左右两个字符串)
--   第一个辅码键的不重复列表为：fullAuxCodes[1]= urpao 
--   第二个辅码键的不重复列表为：fullAuxCodes[2]= urhafi
-- -----------------------------------------------
function AuxFilter.fullAux(env, word)
    local fullAuxCodes = {}
    for _, codePoint in utf8.codes(word) do
        local char = utf8.char(codePoint)
        local charAuxCodes = AuxFilter.aux_code[char] -- 每个字的辅助码组
        if charAuxCodes then
            for _, code in ipairs(charAuxCodes) do
                for i = 1, #code do
                    fullAuxCodes[i] = fullAuxCodes[i] or {}
                    table.insert(fullAuxCodes[i], code:sub(i, i))
                end
            end
        end
    end

    -- 将表格转换为字符串
    for i, chars in pairs(fullAuxCodes) do
        fullAuxCodes[i] = table.concat(chars, "")
    end
    return fullAuxCodes
end



-----------------------------------------------
-- 判斷 auxStr 是否匹配 fullAux  --修改为了宽松匹配
-----------------------------------------------
function AuxFilter.match(fullAux, auxStr)
    if #fullAux == 0 then
        return false
    end
    

    local firstKeyMatched = fullAux[1]:find(auxStr:sub(1, 1)) ~= nil
    local secondKeymatched = fullAux[2]:find(auxStr:sub(1, 1)) ~= nil
    -- 如果辅助码只有一个键，且第一个键匹配两辅码中任意一个，则返回 true
    if #auxStr == 1 then
        -- 为了与断句的逻辑统一,还是不加这个分支了
        -- if AuxFilter.matchmode==1 then
        --     return firstKeyMatched
        -- end
        
        return firstKeyMatched
    end
    -- 宽松模式下如果辅助码有两个或以上,有效组合的排列都有效  严格模式下 顺序一致有效
    local auxStr1 = auxStr:sub(1,1)
    local auxStr2 = auxStr:sub(2,2)
    local fiestKeymatched = fullAux[1]:find(auxStr:sub(2, 2)) ~= nil
    local secondKeyMatched = fullAux[2] and fullAux[2]:find(auxStr:sub(2, 2)) ~= nil
    local mark = false
    for i=1,#fullAux[1] do
        local f1 = fullAux[1]:sub(i,i)
        local f2 = fullAux[2]:sub(i,i)
        local f1m = f1 == auxStr1
        local f2m = f2 == auxStr2
        if f1m and f2m then
            mark = true
            break
        end
    end
    return mark
end
local function split_pinyin(pinyin_str)
    if not pinyin_str then return {} end
    local syllables = {}
    for syllable in pinyin_str:gmatch("[^ ]+") do
        table.insert(syllables, syllable)
    end
    return syllables
end

function slice(tbl, start_idx, end_idx)
    local sliced = {}
    for i = start_idx, end_idx do
        table.insert(sliced, tbl[i])
    end
    return sliced
end
--计算 制定长度切片元素的长度和
local function sum_lengths(slice, n)
    local total = 0
    for i = 1, n do
        local str = slice[i]
        if str then
            total = total + #str
        end
    end
    return total
end

local function transform_preedit(tbl,n)
    local result = {}
    for i = 1,n do
        local jp = tbl[i]
        if jp then
            local rs = jp
            if AuxFilter.preedit_trans then
                rs = AuxFilter.preedit_trans:apply(jp,true)
            end
            result[i] = rs
        end
    end
    return result
end 
-- 定义一个候选类
local candisub= {}
candisub.__index = candisub

-- 构造函数
function candisub:new(cand,s_len)
    local self = setmetatable({}, candisub)
    self.cand = cand
    self.type = cand.type
    self.ftext = cand.text
    self.line = false
    local rawflag = true
    local preedit_flag = true
    if cand:get_dynamic_type() == "Shadow" then
        self.ftext = cand:get_genuine().text
        rawflag = false
    end
    if cand.type =="completion" or cand.type:find("table") then
        preedit_flag = false
    end
    local preeditls = split_pinyin(cand.preedit)
    local rlen = #preeditls
    local zlen = utf8len(cand.text)
    local slen = s_len or zlen
    local len = slen
    if rlen == zlen then
        self.line = true
        local ficompensate =  AuxFilter.rightcompen - AuxFilter.leftcompen
        if ficompensate>0 then
           ficompensate = 0
        end
        if ficompensate~=0 or s_len ~=nil then
            if s_len then
               AuxFilter.firstcand_len = s_len
               AuxFilter.last_fist_commit = {}
            end
            AuxFilter.prelen = AuxFilter.prelen or AuxFilter.firstcand_len + ficompensate
            local prelen = AuxFilter.prelen
            if prelen<=rlen then
                len = prelen
                if len<1 then
                    len = 1
                end
                local textsub = utf8sub(cand.text,1,len)
                local fend = sum_lengths(preeditls,len)
                fend = cand._start + fend
                self.cand = Candidate(cand.type,cand._start,fend,textsub,cand.comment)
                local preedit = table.concat(slice(preeditls,1,len), " ")
                if preedit_flag then
                    preedit = table.concat(transform_preedit(preeditls,len), " ")
                end
                if rawflag then
                    self.cand.preedit = preedit
                else
                    self.cand:get_genuine().preedit = preedit
                end
                return self
            end

        end
    else 
    end
    self.cand = Candidate(cand.type,cand._start,cand._end,cand.text,cand.comment)
    local preedit = table.concat(slice(preeditls,1,rlen), " ")
    if preedit_flag then
        preedit = table.concat(transform_preedit(preeditls,rlen), " ")
    end
    if rawflag then
        self.cand.preedit = preedit
    else
        self.cand:get_genuine().preedit =preedit
    end
    return self
end
-- 返回指定长度的候选
function AuxFilter.yield_candisub(cand)
    local finalcandi = cand
    if (AuxFilter.yieldset[finalcandi.cand.text]~=nil)then
        return    
    end
    AuxFilter.last_fist_commit = AuxFilter.last_fist_commit or {}
    -- logdic("aaa")
    AuxFilter.counter = AuxFilter.counter or 0
    AuxFilter.auxStr = AuxFilter.auxStr or ""
    if AuxFilter.counter == 0 then
        if #AuxFilter.auxStr == 1 then
            if AuxFilter.last_fist_commit[1] == finalcandi.cand.text then
                return
            end
        elseif #AuxFilter.auxStr == 2 then
            if AuxFilter.last_fist_commit[1] == finalcandi.cand.text or AuxFilter.last_fist_commit[2] == finalcandi.cand.text then
                return
            end
        end
    end
    if AuxFilter.turned~=true then
        AuxFilter.yieldset[finalcandi.cand.text] = true
    end
    if AuxFilter.skipc<=0 then
        AuxFilter.counter = AuxFilter.counter+1
        if AuxFilter.counter == 1 then
            AuxFilter.firstcand_len = utf8len(finalcandi.cand.text)
            if #AuxFilter.auxStr == 0 then
                AuxFilter.last_fist_commit[1] = finalcandi.cand.text
            elseif #AuxFilter.auxStr == 1 then
                AuxFilter.last_fist_commit[2] = finalcandi.cand.text
            end
        else
        end
        local cand = finalcandi.cand
        yield(finalcandi.cand)
    else
        AuxFilter.skipc=AuxFilter.skipc-1
    end

end


-- 辅码与音码匹配与否
local function boolaux(tab)
    local mark = false
    if tab then
        if table.size(tab)~=0 then
        mark = true
        end
    
end
return mark
end
local function combmath(aux,tab)
    local mark = true --;;这种空辅码也返回true也就是断在头部
    if AuxFilter.matchmode ==0 then
        --宽匹配下无关辅码顺序
        if #aux~=0 then
            if not (boolaux(tab[aux]) or boolaux(tab[aux:reverse()])) then --
                mark = false
            end
        end
    elseif AuxFilter.matchmode==1 then
        if #aux~=0 then
            if not boolaux(tab[aux]) then
                mark = false
            end
        end
    end


    -- log.info(aux,mark)
return mark
end
local function main_main(env,cand)
    cand = candisub:new(cand)

    local auxCodes = AuxFilter.aux_code[cand.ftext] -- 僅單字非 nil
    -- logdic(cand.text)
    local fullAuxCodes = AuxFilter.fullAux(env, cand.ftext)
    -- 給待選項加上輔助碼提示
    if AuxFilter.show_aux_notice and auxCodes and #auxCodes > 0 then
        local codeComment = table.concat(auxCodes, ',')
        cand.cand.comment = cand.cand.comment .. '(' .. codeComment .. ')'
    end
    -- 過濾輔助碼
    if #(AuxFilter.auxStr) == 0 then
        -- 沒有輔助碼、不需篩選，直接返回待選項
        AuxFilter.yield_candisub(cand)
    elseif #(AuxFilter.auxStr) > 0 and fullAuxCodes and  AuxFilter.match(fullAuxCodes, AuxFilter.auxStr) then
        -- 匹配到辅助码的待选项，直接插入到候选框中( 获得靠前的位置 )
        AuxFilter.yield_candisub(cand)
    else
        -- 待选项字词 没有 匹配到当前的辅助码，插入到列表中，最后插入到候选框里( 获得靠后的位置 )
        -- table.insert(insertLater, cand)
        -- 更新逻辑：没有匹配上就不出现再候选框里，提升性能
    end
end
local function best_match(list, key)
    local best = nil
    local best_len = 0
    for _, item in ipairs(list) do
        if item:sub(1, #key) == key then
            if #key > best_len then
                best = item
                best_len = #key
            end
        end
    end
    return best
end
--- 分支一 原来的功能
function AuxFilter.main1(input,env)
    env.notifiermark = 1  --辅筛情况下的 选词后的逻辑标记 变为 1
    -- 分割部分正式開始
    AuxFilter.auxStr = ""
    AuxFilter.funccode = ""
    local localSplit = AuxFilter.inputCode:match(AuxFilter.trigger_key_pattern .. "([^"..AuxFilter.trigger_key_pattern.."]+)")
    if localSplit then
        AuxFilter.auxStr = string.sub(localSplit, 1, 2)
        AuxFilter.funccode = string.gsub(localSplit,AuxFilter.auxStr,"",1)
    --[[
    除去两位辅码剩余的判定为功能码
    为什么这里也要引入偏移量?
    因为有时筛出的词长度长,第一页内有包含目的词的词,通过功能码可以上修改候选长度.
]]

    end
    AuxFilter.leftcompen = countSubstringOccurrences(AuxFilter.funccode,"a") + 2* countSubstringOccurrences(AuxFilter.funccode,"s") --左偏移量 
    AuxFilter.rightcompen = countSubstringOccurrences(AuxFilter.funccode,"d") + 2 * countSubstringOccurrences(AuxFilter.funccode,"f") -- 右偏移
    AuxFilter.skipc = countSubstringOccurrences(AuxFilter.funccode,"w")
    -- 更新逻辑：没有匹配上就不出现再候选框里，提升性能
    AuxFilter.counter = 0 -- 计数返回候选数量
    local firstcandi = ""      -- 第一个候选也就是最长的那个
    local index=0  --为了获取第一个候选的判断变量
    for cand in input:iter() do
        if (AuxFilter.single_flag  and #split_pinyin(cand.preedit) == 1) or (not AuxFilter.single_flag) then
            index = index+1
            --第一个候选词 额外逻辑
            if index==1 then
                firstcandi = cand
                main_main(env,cand)   
                break
            end

        end

    end

    for value in input:iter() do
        main_main(env,value)
    end
    if AuxFilter.turned==true then
        AuxFilter.turned = false
    end
    --如果辅筛没筛出来,提示你进行辅断
    if AuxFilter.counter==0 then
        local commentfirst =  "无匹配"
        local inputspls =  split_pinyin(firstcandi.preedit)
        local firstcandi = candisub:new(firstcandi)
        if AuxFilter.longcandimodify_flag then
            local matchybtab = {} --辅码可以组合的未翻译的音码的集合
            if firstcandi.line then
                for index, value in ipairs(inputspls) do
                    local zi = utf8sub(firstcandi.ftext,index,index)
                    local best_value = best_match(AuxFilter.zi_to_yin[zi],value)
                    local auxtab = AuxFilter.comb_code[value] or AuxFilter.comb_code[best_value]
                    if combmath(AuxFilter.auxStr,auxtab) then
                        table.insert(matchybtab,tostring(index).."." .. utf8sub(firstcandi.cand.text,index,index))
                    end
                end
            end
            if #matchybtab~=0 then
                commentfirst = table.concat(matchybtab,"--")
            end
        else
            commentfirst = "無匹配"
        end
        firstcandi.cand.comment = commentfirst
        yield(firstcandi.cand)
    end
end



--- 无触发分支
function AuxFilter.defaultmain(input,env)
    for cand in input:iter() do
        -- logdic(cand.preedit)

        -- logdic(AuxFilter.inputCode .. "|"..cand.type .. "|"..cand.text.."|"..cand.comment.."|"..cand.preedit)
        local preeditls = split_pinyin(cand.preedit)
        local preedit =  table.concat(transform_preedit(preeditls,#preeditls), " ")
        if cand.type =="completion" or cand.type:find("table") then
            preedit =  table.concat(slice(preeditls,1,#preeditls), " ")
        end
        if cand.type =="Shadow" or cand.type == "simplified" then
            local rawcand = cand:get_genuine()
            rawcand.preedit = preedit
        else
            cand.preedit = preedit
        end
        yield(cand)
    end
    
end



--- 句子修改分支
function AuxFilter.longcandimodify(input,env)
    local branchmark = 1 --在句子修改分支中的分支  1-断句分支  2-修音分支 3-云词分支
    env.notifiermark = 2  --断句情况下的 选词后的逻辑标记 变为 2
    ---获取第一个候选也就是最长的那个,,怎么简单的获取,
    local firstcandi =""
    for cand in input:iter() do
        AuxFilter.ftext = cand.text
        if cand.type =="Shadow" or cand.type == "simplified" then
            AuxFilter.ftext= cand:get_genuine().text
        end
        firstcandi = cand
        break
    end
    local auxcode = AuxFilter.inputCode:match(AuxFilter.trigger_key_pattern .. "(%a*)" .. AuxFilter.trigger_key_pattern) --辅码部分
    -- log.info("auxcode",auxcode)
    local funccode = AuxFilter.inputCode:match(AuxFilter.trigger_key_pattern .. "%a*" .. AuxFilter.trigger_key_pattern .. "+(%a*)") --功能码部分
    -- log.info("fucncode",funccode)
    local ybmodif = funccode:match("s(%a+)") --功能码部分捕获的修音的音码
        
        
    if ybmodif then 
        --进入修音分支处理
        branchmark=2
        funccode = string.gsub(funccode,"s" .. ybmodif,"") --减掉修音部分的功能码,为后续统计偏移做准备
    end
    -- log.info("音码",ybmodif)
    -- log.info("funccode",funccode)
    AuxFilter.leftcompen = countSubstringOccurrences(funccode,"a") --左偏移量
    AuxFilter.rightcompen = countSubstringOccurrences(funccode,"d") + 2 * countSubstringOccurrences(funccode,"f") -- 右偏移量
    -- local inputspls = split_by_indices(AuxFilter.removetransdInput, AuxFilter.stindex) --未翻译的音码集合
    local inputspls =  split_pinyin(firstcandi.preedit)
    AuxFilter.ficompensate = utf8len(firstcandi.text) --初始化偏移量  默认在断点尾部
    local passnum = countSubstringOccurrences(AuxFilter.inputCode,AuxFilter.trigger_key) -2  --计算跳过匹配数  功能码中 ; 的作用
    -- log.info(inputspls[1])
    --确定最终断点位置
    local matchedmark = false  --整句辅码是否有有效配对
    
    for index, value in ipairs(inputspls) do
        local zi = utf8sub(AuxFilter.ftext,index,index)
        local best_value = best_match(AuxFilter.zi_to_yin[zi],value)
        local auxtab = AuxFilter.comb_code[value] or AuxFilter.comb_code[best_value]
        -- logdic(str_table(auxtab))

        if combmath(auxcode,auxtab) then
            AuxFilter.ficompensate = index
            matchedmark= true
            if passnum==0 then
            break
            end
            passnum=passnum-1

        end
    end
    -- if compensate<=0 then
    --     compensate=1
    -- end
    if matchedmark then
       AuxFilter.ficompensate = AuxFilter.ficompensate -1  --减1是要断在作用词之前  
    end
    --在断点处修音逻辑
    if branchmark==2 then
        env.notifiermark = 3 --修音模式下,选词后的逻辑的标志变为3
        local wrongyb = inputspls[AuxFilter.ficompensate+1]
        inputspls[AuxFilter.ficompensate+1] = ybmodif
        local inputcode2 = table.concat(inputspls,"")  --修改后的未翻译音码连接为字符串
        -- log.info(inputcode2)
        AuxFilter.ybmodifiedcode = AuxFilter.transdcodei .. inputcode2 .. AuxFilter.trigger_key  --修改后的音码 + 引导键

        AuxFilter.removetransdInput = inputcode2:sub(1,-2)
        yield(Candidate(firstcandi.type,firstcandi._start,firstcandi._start,"",wrongyb .."->" .. ybmodif))  --"确定"  候选项
    
    --在断点处断句逻辑
    elseif branchmark==1 then
        local comment = ""
        -- logdic("断句"..firstcandi.text .. AuxFilter.ficompensate)
        local finalcandi = candisub:new(firstcandi,AuxFilter.ficompensate)
        -- logdic("断句"..finalcandi.cand.text)
        AuxFilter.yield_candisub(finalcandi)
    end
    if not matchedmark then
        comment = "辅码无匹配"
    end
    finalcandi.comment = comment
    yield(finalcandi)
end




-- 使用示例
function AuxFilter.Update_codes(ctx)
    local context = ctx
    --- 预处理输入码
    AuxFilter.inputCode = context.input --输入码
    -- log.info("输入码",AuxFilter.inputCode)
    AuxFilter.precode = context:get_preedit().text --预处理码 
    -- logdic(context:get_script_text())
    AuxFilter.removeAuxInput = AuxFilter.inputCode:match("^(%a+)" .. AuxFilter.trigger_key_pattern.."-")  or ""--纯输入引导键前的部分
    -- log.info("引导键前的输入",AuxFilter.removeAuxInput)
    AuxFilter.removeAuxprecode = AuxFilter.precode:match("^([^" .. AuxFilter.trigger_key_pattern .. "]*)" .. AuxFilter.trigger_key_pattern.."-") or "" --去除辅码后的pre
    -- log.info("引导键前的预处理",AuxFilter.removeAuxprecode)
    -- logdic("引导键前的预处理" .. AuxFilter.removeAuxprecode)
    AuxFilter.removetransdInput= AuxFilter.removeAuxprecode:match("^[^a-z]*(%a*)") or ""  --翻译过后引导键前的未翻译部分  
    -- log.info("引导键前的未翻译",AuxFilter.removetransdInput) 
    AuxFilter.transdcode = string.gsub(AuxFilter.removeAuxprecode,AuxFilter.removetransdInput,"")  --已翻译部分
    -- log.info("已翻译部分",AuxFilter.transdcode)
    AuxFilter.transdcodei = string.gsub(AuxFilter.removeAuxInput,AuxFilter.removetransdInput,"")  --已翻译字母部分

    -- log.info("已翻译的字母",AuxFilter.transdcodei)
end
local function switch_single_char(ctx)
    if AuxFilter.single_flag == true then
        AuxFilter.single_flag = false
    elseif AuxFilter.single_flag == false then
        AuxFilter.single_flag = true
    end
    AuxFilter.turned = true
    ctx.input = ctx.input:gsub("`","")
    AuxFilter.Update_codes(ctx)
    -- logdic(AuxFilter.inputCode)
end
function AuxFilter.func(input, env) 
    -- log.info("输入码",AuxFilter.inputCode)
    -- logdic("出發")
    env.notifiermark = -1
    AuxFilter.yieldset = {}
    AuxFilter.leftcompen = 0
    AuxFilter.rightcompen = 0
    AuxFilter.skipc = 0
    AuxFilter.counter = 0
    AuxFilter.prelen = nil -- 第一個詞的長度 用於偏離計算
    AuxFilter.single_flag = AuxFilter.single_flag or false --標記篩選類型是哪個
    local ctx = env.engine.context
    AuxFilter.Update_codes(ctx)
    -- 分流
    local pattern_main1 = "^%a+" .. AuxFilter.trigger_key_pattern ..'%a*$'  --辅筛分支的正则
    local pattern_long = "^%a+" ..AuxFilter.trigger_key_pattern .. "%a*" .. AuxFilter.trigger_key_pattern .."+%a*$" --长句修改分支的正则
    local pattern_singlechar_switch = "^%a+" .. AuxFilter.trigger_key_pattern .."`"..'%a*$'  -- 单字输入分支
-- 
    if string.match(AuxFilter.inputCode,pattern_main1)then
        -- log.info("进入分支1",AuxFilter.inputCode)
        local composition = env.engine.context.composition
        if(not composition:empty()) then
            local segment = composition:back()
            if AuxFilter.single_flag then 
                segment.prompt = "单字筛选分支"
            end
        end
        -- log.info("进入分支1",AuxFilter.inputCode)
        AuxFilter.main1(input,env)
    elseif string.match(AuxFilter.inputCode,pattern_long) then
        AuxFilter.last_fist_commit = nil
        AuxFilter.longcandimodify(input,env) 
        -- log.info("进入分支2",AuxFilter.inputCode)    
    elseif string.match(AuxFilter.inputCode,pattern_singlechar_switch) then
        -- logdic("进入分支3",AuxFilter.inputCode)
        switch_single_char(env.engine.context)
        AuxFilter.main1(input,env)
    else
        AuxFilter.last_fist_commit = nil
        AuxFilter.defaultmain(input,env)
    end
    
end

function AuxFilter.fini(env)
    -- log.info("fini")
    env.notifier:disconnect()
end
return AuxFilter
