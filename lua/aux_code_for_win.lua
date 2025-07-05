local http = require("simplehttp")
http.TIMEOUT = 30
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

--- http 引入
local baseurl = "http://10.18.18.106:8080"
local function fetch_api_config()
    local config_url = baseurl .. "/config"
    local res = http.request(config_url)
    if res == "" then
        return nil
    end
    -- 解析纯文本配置
    local config_table = {}
    -- string.gmatch 会遍历响应文本中的每一行
    for line in res:gmatch("[^\r\n]+") do
        -- string.match 从每一行中提取出第一个非空字符串(key)和之后的所有内容(value)
        local key, value = line:match("^(%S+)%s+(.*)$")
        if key and value then
            -- logdic(key..value)
            config_table[key] = value
            -- print("已加载配置: " .. key .. " -> " .. value) -- 用于调试
        end
    end
    return config_table
end

local luyz = fetch_api_config()
local function onereq(key,inp)
    local lu = luyz[key] or ""
    local url = baseurl..lu..inp
    local res = http.request(url)
    return res
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
    local defaultuserprefer = {
        path = "ZRM_Aux-code",
        showor = "on",
        trigger = ";",
        ["switch"] = "`",  -- 注意这里
        ph = ",",
        matchmode = "s"
    }
    local keys = {"path", "showor","trigger","switch", "ph","matchmode"}
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
    -- 設定預設觸發鍵為分號，並從配置中讀取自訂的觸發鍵
    AuxFilter.trigger_key = defaultuserprefer["trigger"]
    AuxFilter.trigger_key_pattern = AuxFilter.trigger_key:gsub("(%W)", "%%%1") -- 處理特殊字符  --正则中应该表现的形式。
    AuxFilter.ph = defaultuserprefer["ph"]
    AuxFilter.ph_pattern = AuxFilter.ph:gsub("(%W)", "%%%1")
    -- 设定是否显示辅助码，默认为显示
    AuxFilter.switch_key = defaultuserprefer["switch"]:gsub("(%W)", "%%%1")
    AuxFilter.show_aux_notice = defaultuserprefer["showor"]
    if AuxFilter.show_aux_notice == "off" then
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
    if AuxFilter.opencc == nil then
        AuxFilter.opencc = Opencc("s2t.json")
    end
    -- 加載輔助碼文件
    -- 不同模式不同处理逻辑
    env.notifier = engine.context.select_notifier:connect(function(ctx)
    if AuxFilter.notifiermark == 1 then
        -- logdic("jr1")
        AuxFilter.main1_notifier(ctx)
    elseif AuxFilter.notifiermark==2 then
        -- logdic("jr2")
        AuxFilter.longcandimodify_notifier(ctx)
    elseif AuxFilter.notifiermark==3 then
        -- logdic("jr3")
        AuxFilter.longcandimodify_ybnotifier(ctx)
    end
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
        if AuxFilter.transedtext ~=nil then
            -- logdic("cccc" .. AuxFilter.transedtext)
            AuxFilter.env.engine:commit_text(AuxFilter.transedtext)
            AuxFilter.transedtext = nil
            ctx:clear()
            return 
        end
        AuxFilter.Update_codes(ctx)
        if AuxFilter.removetransdInput ~= "" then
            AuxFilter.aux_left = AuxFilter.aux_left or ""
            -- logdic("有輔助碼"..AuxFilter.aux_left)
            -- 給詞尾自動添加分隔符，上面的 re.match 會把分隔符刪掉
            ctx.input = AuxFilter.removeAuxInput .. AuxFilter.trigger_key ..AuxFilter.aux_left
        else
            -- 剩下的直接上屏
            ctx.input = AuxFilter.removeAuxInput
            AuxFilter.single_flag = false
            ctx:commit()
            -- local cand = Candidate("pre",0,0,"测试","test")
            -- yield(cand)
        end
    end







--- notifier longcandimodify模式  (断句模式)
    ----------------------------
    -- 保持輔助碼分隔符和原辅码存在 --
    ----------------------------
function AuxFilter.longcandimodify_notifier(ctx)
    AuxFilter.Update_codes(ctx)
    -- ctx.input = AuxFilter.removeAuxInput
    AuxFilter.single_flag = false
    local auxcode = AuxFilter.inputCode:match(AuxFilter.trigger_key_pattern.. "(%a*)".. AuxFilter.trigger_key_pattern)
    if AuxFilter.removetransdInput ~= "" then
        ctx.input = AuxFilter.removeAuxInput .. AuxFilter.trigger_key .. auxcode
    else
        ctx.input = AuxFilter.removeAuxInput
        ctx:commit()
    end
    end

--- notifier longcandimodify2模式(修音模式) 
function AuxFilter.longcandimodify_ybnotifier(ctx)
    -- log.info("modifyinput",AuxFilter.ybmodifiedcode)
    AuxFilter.single_flag = false
    ctx.input = AuxFilter.ybmodifiedcode
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


local function split(str, sep)
    local result = {}
    if str == "" then
        return result
    end
    for part in string.gmatch(str, "([^" .. sep .. "]+)") do
        table.insert(result, part)
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
    local mixedCodes = {}      -- 音码 -> {辅码=true}
    
    for line in file:lines() do
        line = line:match("[^\r\n]+")  -- 去除换行符
        local zi, fu, yb = string.match(line, "^([^\t]+)\t([^\t]+)\t?([^\t]*)$")
        if zi and fu and yb then
            local fuls = split(fu, ",")
            -- 1. 去重插入 auxCodesSet
            for _, fuone in ipairs(fuls) do
                auxCodesSet[zi] = auxCodesSet[zi] or {}
                auxCodesSet[zi][fuone] = true
                -- 3. mixedCodes 构建为 set
                if yb ~= "" then
                    mixedCodes[yb] = mixedCodes[yb] or {}
                    mixedCodes[yb][fuone] = true
                end
            end
            -- 2. 去重插入 zi_to_yin_set
            zi_to_yin_set[zi] = zi_to_yin_set[zi] or {}
            zi_to_yin_set[zi][yb] = true
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
    -- 预分配两个位置，因为辅码最多两位
    local fullAuxCodes = {{}, {}}
    
    for _, codePoint in utf8.codes(word) do
        local char = utf8.char(codePoint)
        local charAuxCodes = AuxFilter.aux_code[char]
        if charAuxCodes then
            for _, code in ipairs(charAuxCodes) do
                table.insert(fullAuxCodes[1], code:sub(1, 1))
                if #code > 1 then
                    table.insert(fullAuxCodes[2], code:sub(2, 2))
                end
            end
        end
    end

    -- 合并字符串
    fullAuxCodes[1] = table.concat(fullAuxCodes[1])
    fullAuxCodes[2] = table.concat(fullAuxCodes[2])
    return fullAuxCodes
end


-----------------------------------------------
-- 判斷 auxStr 是否匹配 fullAux 
-----------------------------------------------
function AuxFilter.match(fullAux, auxStr)
    -- 空辅码表直接返回 false
    if #fullAux == 0 then
        return false
    end

    -- 处理单辅码匹配
    if #auxStr == 1 then
        local char = auxStr:sub(1, 1)
        local firstMatch = fullAux[1]:find(char) ~= nil
        local secondMatch = fullAux[2]:find(char) ~= nil
        return firstMatch or 
               (AuxFilter.matchmode == 0 and secondMatch)
    end

    -- 处理双辅码匹配
    local aux1, aux2 = auxStr:sub(1,1), auxStr:sub(2,2)
    for i = 1, #fullAux[1] do
        local f1, f2 = fullAux[1]:sub(i,i), fullAux[2]:sub(i,i)
        -- 检查正序匹配
        if f1 == aux1 and f2 == aux2 then
            return true
        end
        
        -- 宽松模式下检查逆序匹配
        if AuxFilter.matchmode == 0 and f2 == aux1 and f1 == aux2 then
            return true
        end
    end
    return false
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
--计算 指定长度切片元素的长度和
local function sum_lengths(slice, n)
    if not slice or n <= 0 then return 0 end
    local total = 0
    for i, str in ipairs(slice) do
        if i > n then break end
        total = total + (str and #str or 0)
    end
    return total
end
local function transform_preedit(tbl, n)
    if not tbl or n <= 0 or not AuxFilter.preedit_trans then return tbl or {} end
    
    local result = {}
    local apply = AuxFilter.preedit_trans.apply
    for i = 1, n do
        result[i] = tbl[i] and apply(AuxFilter.preedit_trans, tbl[i], true) or tbl[i]
    end
    return result
end
-- 定义一个候选类
local candisub= {}
candisub.__index = candisub

--[[
candisub 构造函数
包装 Rime Candidate 对象，主要处理候选词截断和 preedit 调整。

参数:
  cand (Candidate): 原始候选词。
  s_len (number, optional): 指定的截断长度（字符数）。
返回:
  candisub: 新的 candisub 实例。
]]
function candisub:new(cand, s_len)
    local self = setmetatable({}, candisub)

    self.rawcand = cand
    self.cand = cand -- 当前处理的候选词，可能被截断后的新 Candidate 替换
    self.type = cand.type
    self.ftext = cand.text -- 原始文本，用于比较或显示
    self.line = false -- 标记是否为线性映射 (输入段数 == 输出字数)

    local rawflag = true       -- true: 修改 self.cand.preedit; false: 修改 genuine cand 的 preedit
    local preedit_flag = true  -- true: 需要转换 preedit 

    -- Shadow Candidate: 使用真实候选词文本，不直接修改 preedit
    if cand:get_dynamic_type() == "Shadow" then
        self.ftext = cand:get_genuine().text
        rawflag = false
    end

    -- completion/table 类型不转换 preedit
    if cand.type == "completion" or cand.type:find("table") then
        preedit_flag = false
    end

    local preeditls = split_pinyin(cand.preedit) -- 分割 preedit, e.g., "ni hao" -> {"ni", "hao"}
    local rlen = #preeditls                     -- preedit 段数
    local zlen = utf8len(cand.text)             -- 文本字符数
    local len = rlen                            -- 最终使用的 preedit 段数，默认为全部
    -- 核心截断逻辑: 仅当输入码数等于输出字数时 (线性) 才考虑截断
    if rlen == zlen then
        self.line = true
        -- 计算补偿值，可能缩短长度
        local ficompensate = math.min(0, AuxFilter.rightcompen - AuxFilter.leftcompen)

        -- 需要截断的条件：补偿值非零 或 指定了 s_len
        if ficompensate ~= 0 or s_len ~= nil then
            -- 如果传入 s_len，重置 AuxFilter 状态
            if s_len then
               AuxFilter.last_fist_commit = {}
            end
            -- 副作用：确定并更新 AuxFilter.prelen (基础长度)
            AuxFilter.prelen = s_len or AuxFilter.firstcand_len or zlen
            local target_prelen = AuxFilter.prelen + ficompensate -- 计算目标长度
            -- 如果目标长度有效且小于原始长度，则进行截断
            if target_prelen <= rlen then
                len = math.max(1, target_prelen) -- 确定最终截断长度 (至少为1)
                -- 创建新的、截断后的 Candidate 对象
                local textsub = utf8sub(cand.text, 1, len)
                local fend = cand._start + sum_lengths(preeditls, len) -- 计算新结束位置
                self.cand = Candidate(cand.type, cand._start, fend, textsub, cand.comment)
                -- 注意: self.cand 现在指向新创建的对象
            end
        end
    end

    -- === 生成并设置最终的 preedit ===
    -- 根据最终长度 `len` 截取 preedit 段
    local final_preedit_parts = slice(preeditls, 1, len)

    -- 如果需要，转换 preedit (如首字母大写)
    if preedit_flag then
        final_preedit_parts = transform_preedit(final_preedit_parts, len)
    end

    -- 合并 preedit 段
    local final_preedit = table.concat(final_preedit_parts, " ")

    -- 将最终 preedit 设置到正确的 Candidate 对象上
    if rawflag or AuxFilter.yieldset[self.ftext] then
        self.cand.preedit = final_preedit -- 设置到 self.cand (可能是新的也可能是原始的)
    else
        -- self.cand:get_genuine().preedit = final_preedit -- 设置到 Shadow 背后的真实 Candidate
    end
    return self
end
function AuxFilter.yield_candisub(cand)
    local finalcandi = cand
    
    -- 快速检查是否已处理 元候选去重
    if AuxFilter.yieldrawset[finalcandi.rawcand.text] then
        return    
    end
    
    -- 初始化变量（使用局部变量提升性能）
    local last_commit = AuxFilter.last_fist_commit or {}
    local counter = AuxFilter.counter or 0
    local aux_str = AuxFilter.auxStr or ""
    local aux_len = #aux_str
    
    -- 处理第一个候选的特殊情况（简化嵌套判断） 动态去除 
    if counter == 0 and aux_len > 0 and aux_len <= 2 then
        if last_commit[1] == finalcandi.rawcand.text or 
           (aux_len == 2 and last_commit[2] == finalcandi.rawcand.text) then
            return
        end
    end
    
    -- 记录非turned轮  准上屏元候选
    if not AuxFilter.turned then
        AuxFilter.yieldrawset[finalcandi.rawcand.text] = true
    end
    -- 处理跳过逻辑 wipe主动去除
    if AuxFilter.skipc > 0 then
        AuxFilter.skipc = AuxFilter.skipc - 1
        return
    end

    -- 检查并记录候选文本  上屏去重
    local cand_text = finalcandi.cand.text
    if AuxFilter.yieldset[cand_text] then
        return
    end

    if not AuxFilter.turned then
        AuxFilter.yieldset[cand_text] = true
    end
    -- 更新计数器和首个候选信息
    AuxFilter.counter = counter + 1
    if counter == 0 then
        AuxFilter.firstcand_len = utf8len(finalcandi.rawcand.text)
        if aux_len < 2 then
            last_commit[aux_len + 1] = finalcandi.rawcand.text
        end
        AuxFilter.last_fist_commit = last_commit
        if aux_len == 1 then
            AuxFilter.one_aux_firstcode = utf8sub(cand_text,1,1)
        end
    end
    -- 提交候选
    ---------- 
    local cand = finalcandi.cand
    local candtext = cand.text
    if AuxFilter.counter == 1 and (AuxFilter.dupc~=1 or AuxFilter.transor) then
        candtext = AuxFilter.transdcode:gsub("‸","") .. cand.text
        -- logdic(candtext)
        if AuxFilter.dupc~=1 then
            candtext = string.rep(candtext, AuxFilter.dupc)
            cand.comment = "复制" .. tostring(AuxFilter.dupc) .. "次"
        end
        if AuxFilter.transor==true then
            if AuxFilter.trans_target == nil then
                candtext = AuxFilter.opencc:convert(candtext)
            else
                -- logdic(AuxFilter.trans_target)
                -- logdic(AuxFilter.trans_target)
                local res = onereq(AuxFilter.trans_target,candtext)
                -- logdic("res"..res)
                if res == "" then
                    cand.comment = AuxFilter.trans_target .. "空引导"
                else
                    candtext = res 
                end
            end
        end
        cand = Candidate(cand.type, 0, cand._end, candtext, cand.comment)
        AuxFilter.transedtext = candtext

    end
    yield(cand)
end
-- 生成辅码组合的函数
-- @param dict: 字典形式 {ab=true, cd=true}
-- @param mode: 's'严格模式生成单字母和完整辅码, 'l'宽松模式生成所有可能组合
-- @return: 数组形式的组合结果
local function two_char_combinations(dict)
    local result = {}
    
    -- 遍历字典中的每个键
    for key in pairs(dict) do
        -- 严格模式：只添加单字母和完整辅码
        if AuxFilter.matchmode == 0 then
            result[key:sub(2,2)] = true
        end
        -- 添加第一个字母
        result[key:sub(1,1)] = true
        -- 添加完整辅码
        result[key] = true
    end
    return result
end
-- 混合匹配
local function combmath(aux, tab)
    -- 空辅码返回true(断在头部)
    if #aux == 0 then
        return true
    end
    
    -- 如果tab为空，直接返回false
    if not tab or not next(tab) then
        return false
    end
    
    -- 生成辅码组合集合
    local fuset = two_char_combinations(tab)
    
    -- 直接检查原始和反转的辅码
    -- 严格模式只检查原始辅码，宽松模式同时检查反转辅码
    return fuset[aux] or (AuxFilter.matchmode == 0 and fuset[aux:reverse()])
end

local function main_main(env,cand)
    local ftext = cand.text
    if cand:get_dynamic_type() == "Shadow" then
        ftext = cand:get_genuine().text
    end

    local auxCodes = AuxFilter.aux_code[ftext] -- 僅單字非 nil
    -- logdic(cand.text)
    local fullAuxCodes = AuxFilter.fullAux(env,ftext)
    -- 給待選項加上輔助碼提示
    if AuxFilter.show_aux_notice and auxCodes and #auxCodes > 0 then
        local codeComment = table.concat(auxCodes, ',')
        cand.comment = cand.comment .. '(' .. codeComment .. ')'
    end
    --置空 外附辅助
    if #(AuxFilter.auxStr) ~= 2 then
        AuxFilter.aux_left = nil
    end
    -- 輔助碼处理
    if #(AuxFilter.auxStr) == 0 then
        -- 沒有輔助碼、不需篩選，直接返回待選項
        -- logdic(AuxFilter.inputCode .. ","..cand.text)
        cand = candisub:new(cand)
        AuxFilter.yield_candisub(cand)
    elseif #(AuxFilter.auxStr) > 0 and fullAuxCodes and  AuxFilter.match(fullAuxCodes, AuxFilter.auxStr) then
        -- 匹配到辅助码的待选项，直接插入到候选框中( 获得靠前的位置 )
        -- logdic(AuxFilter.inputCode .. ","..cand.text)
        cand = candisub:new(cand)
        AuxFilter.yield_candisub(cand)
    --对于二三四词的特殊处理
    elseif #(AuxFilter.auxStr) == 2 and utf8len(cand.text) == 2 then
        -- 判断字符是否在列表元素的首字符位置
        local function isCharInFirstPosition(char, list)
            if not char or not list then
                return false
            end
            for _, item in ipairs(list) do
                if type(item) == "string" and #item > 0 then
                    if item:sub(1, 1) == char then
                        return true
                    end
                end
            end
            
            return false
        end
        local firstchar = utf8sub(cand.text,1,1)
        local firsaux = AuxFilter.auxStr:sub(1,1)
        local firstchar_aux = AuxFilter.aux_code[firstchar]
        local first_bool = isCharInFirstPosition(firsaux, firstchar_aux)
        if not first_bool then
            return
        end
        local secondchar = utf8sub(cand.text,-1,-1)
        local secondaux = AuxFilter.auxStr:sub(2,2)
        local secondchar_aux = AuxFilter.aux_code[secondchar]
        local second_bool = isCharInFirstPosition(secondaux, secondchar_aux)
        if second_bool then
            AuxFilter.one_aux_firstcode = AuxFilter.one_aux_firstcode or ""
            if firstchar ~= AuxFilter.one_aux_firstcode  then
                -- logdic("firstchar:"..firstchar.."firstcand:".. AuxFilter.one_aux_firstcode)
                return
            end
            if AuxFilter.last_fist_commit[2] ~= cand.text then
                cand.comment = "**"..cand.comment
                cand = candisub:new(cand)
                AuxFilter.yield_candisub(cand)
            end
        end
        if AuxFilter.aux_left=="" then
            return
        end
        if AuxFilter.counter~=0 then
            return
        end 
        if firstchar == AuxFilter.one_aux_firstcode then
            AuxFilter.aux_left = secondaux
            -- logdic("auxleft为"..secondaux)
            cand.comment = "*x"..cand.comment
            AuxFilter.auxleftcandi = AuxFilter.auxleftcandi or {}
            table.insert(AuxFilter.auxleftcandi,cand)
        end
        return
    else
        -- 待选项字词 没有 匹配到当前的辅助码，插入到列表中，最后插入到候选框里( 获得靠后的位置 )
        -- table.insert(insertLater, cand)
        -- 更新逻辑：没有匹配上就不出现再候选框里，提升性能
    end
end
local function best_match(list, key)
    if list == nil then
        return key
    end
    local best = nil
    local best_len = 0

    for _, item in ipairs(list) do
        if item:sub(1, #key) == key then
            best = item
            break  -- 找到就返回
        end
    end

    -- 如果没有匹配，就返回第一个元素（如果存在）
    if not best and #list > 0 then
        best = list[1]
    end

    return best
end
--- 功能码解析
function parseIntelligentCode(funccode)
    -- 1. 初始化结果
    -- logdic(funccode)
    local result = {
        leftcompen = 0,
        rightcompen = 0,
        skipc = 0,
        dupc = 1,
        transor = false,
        trans_target = nil -- 't' 功能的目标字符
    }

    if not funccode or funccode == "" then
        return result
    end

    local i = 1
    local n = #funccode

    -- 2. 解析偏移段 (w, a, s, d, f)
    while i <= n do
        local char = string.sub(funccode, i, i)
        if char == 'w' then
            result.skipc = result.skipc + 1
        elseif char == 'a' then
            result.leftcompen = result.leftcompen + 1
        elseif char == 's' then
            result.leftcompen = result.leftcompen + 2
        elseif char == 'd' then
            result.rightcompen = result.rightcompen + 1
        elseif char == 'f' then
            result.rightcompen = result.rightcompen + 2
        else
            break
        end
        i = i + 1
    end

    -- 3. 解析功能段
    while i <= n do
        local guide_char = string.sub(funccode, i, i)
        -- 功能引导键: 'c'
        if guide_char == 'c' then
            i = i + 1
            -- result.dupc = result.dupc + 1
            while i <= n do
                local op_char = string.sub(funccode, i, i)
                if op_char == 'c' then
                    result.dupc = result.dupc + 1
                elseif op_char == 'v' then
                    result.dupc = result.dupc * 2
                elseif op_char == 'b' then
                    result.dupc = result.dupc ^ 2
                elseif op_char == 'n' then
                    result.dupc = result.dupc - 1
                else
                    break
                end
                i = i + 1
            end
        -- 功能引导键: 't'
        elseif guide_char == 't' then
            i = i + 1
            result.transor = true
            if i <= n then
                local start_pos = i
                result.trans_target = string.sub(funccode,start_pos,#funccode)
                i = n
            end
        -- 其他字符跳过
        else
            i = i + 1
        end
    end

    return result
end



--- 分支一：辅助码筛选功能
function AuxFilter.main1(input, env)
    -- 初始化环境和变量
    -- logdic("进入")
    local function process_input()
        AuxFilter.auxStr, AuxFilter.funccode = "", ""
        local localSplit = AuxFilter.inputCode:match(AuxFilter.trigger_key_pattern .. "([^"..AuxFilter.trigger_key_pattern.."]+)")
        if localSplit then
            -- logdic("localsp"..localSplit)
            AuxFilter.auxStr = string.sub(localSplit, 1, 2)
            AuxFilter.funccode = string.gsub(localSplit, AuxFilter.auxStr, "", 1)       
            AuxFilter.auxStr = AuxFilter.auxStr:gsub(AuxFilter.ph_pattern,"")
            -- logdic(AuxFilter.auxStr)
        end
        -- local count = countSubstringOccurrences
        -- AuxFilter.leftcompen = count(AuxFilter.funccode, "a") + 2 * count(AuxFilter.funccode, "s")
        -- AuxFilter.rightcompen = count(AuxFilter.funccode, "d") + 2 * count(AuxFilter.funccode, "f")
        -- AuxFilter.skipc = count(AuxFilter.funccode, "w")
        -- for i = 1, #AuxFilter.funccode do
        -- local char = string.sub(AuxFilter.funccode, i, i)
        -- if char == 'c' then
        --     AuxFilter.dupc = AuxFilter.dupc + 1
        -- elseif char == 'v' then
        --     AuxFilter.dupc = AuxFilter.dupc * 2
        -- elseif char == 'b' then
        --     AuxFilter.dupc = AuxFilter.dupc ^ 2
        -- elseif char == 'n' then
        --     AuxFilter.dupc = AuxFilter.dupc - 1
        -- elseif char == "t" then
        --     AuxFilter.transor = true
        -- end
        -- end
        local result = parseIntelligentCode(AuxFilter.funccode)
        AuxFilter.leftcompen = result.leftcompen
        AuxFilter.rightcompen = result.rightcompen
        AuxFilter.skipc = result.skipc
        AuxFilter.dupc = result.dupc
        AuxFilter.transor = result.transor
        AuxFilter.trans_target = result.trans_target
        
    end

    -- 处理候选词
    local function process_candidates()
        local firstcandi, rawpreedit
        local condition = function(cand)
            return (AuxFilter.single_flag and #split_pinyin(cand.preedit) == 1) or (not AuxFilter.single_flag)
        end
        
        -- 获取并处理第一个候选词
        for cand in input:iter() do
            if condition(cand) then
                firstcandi, rawpreedit = cand, cand.preedit
                main_main(env, cand)
                break
            end
        end

        
        -- 处理剩余候选词
        for cand in input:iter() do
            if condition(cand) then
                main_main(env, cand)
                -- logdic("iuiu"..cand.text)
            end
        end
        -- 处理特殊词

        --  辅助字符串长度为2
        local is_aux_str_len_two = (#(AuxFilter.auxStr) == 2)
        --  首候选非单字
        local is_first_candi_not_single_char = (utf8len(firstcandi.text) ~= 1)
        -- 当通用条件1和2都满足时
        if is_aux_str_len_two and is_first_candi_not_single_char then
            if AuxFilter.counter > 0 then
                -- 计数器大于0: 重置 aux_left
                AuxFilter.aux_left = ""
            elseif AuxFilter.counter == 0 then
                -- 计数器等于0: 处理 auxleftcandi
                AuxFilter.auxleftcandi = AuxFilter.auxleftcandi or {}
                for _, v in ipairs(AuxFilter.auxleftcandi) do
                    v = candisub:new(v,1)
                    AuxFilter.yield_candisub(v) -- 输出子候选
                end
            end
        end
            -- 重置计数器
        AuxFilter.auxleftcandi = nil
        -- logdic("结束")
        return firstcandi, rawpreedit
    end

    -- 处理无匹配情况
    local function handle_no_match(firstcandi, rawpreedit)
        if not firstcandi then return end
        
        local inputspls = split_pinyin(rawpreedit)
        firstcandi.preedit = rawpreedit
        local cand = candisub:new(firstcandi)
        local candtext_list = {}
        
        for i = 1, utf8len(cand.cand.text) do
            candtext_list[i] = utf8sub(cand.cand.text, i, i)
        end
        
        if AuxFilter.longcandimodify_flag and (not AuxFilter.single_flag) and cand.line then
            local matchybtab = {}
            for index, value in ipairs(inputspls) do
                local zi = utf8sub(cand.ftext, index, index)
                local best_value = best_match(AuxFilter.zi_to_yin[zi], value)
                local auxtab = AuxFilter.comb_code[value] or AuxFilter.comb_code[best_value] or {}
                
                if combmath(AuxFilter.auxStr, auxtab) then
                    table.insert(matchybtab, index .. "." .. candtext_list[index])
                    candtext_list[index] = "<" .. candtext_list[index]
                end
            end
            if #matchybtab == 0 then
                candtext_list[1] = "❗" .. candtext_list[1]
            end
        elseif AuxFilter.longcandimodify_flag and AuxFilter.single_flag and cand.line then
            candtext_list[1] = "❗" .. candtext_list[1]
        end
        cand.cand = Candidate(cand.cand.type, cand.cand._start, cand.cand._start, table.concat(candtext_list), cand.cand.comment)
        yield(cand.cand)
    end

    -- 主流程执行
    process_input()
    AuxFilter.counter = 0
    local firstcandi, rawpreedit = process_candidates()
    AuxFilter.turned = false
    if AuxFilter.counter == 0 then
        handle_no_match(firstcandi, rawpreedit)
    end
end

--- 无触发分支：直接处理候选词
function AuxFilter.defaultmain(input, env)
    for cand in input:iter() do
        AuxFilter.yield_candisub(candisub:new(cand))
    end
end

--- 句子修改分支：处理断句和修音
function AuxFilter.longcandimodify(input, env)
    -- 初始化环境
    local branchmark = 1
    AuxFilter.notifiermark = 2
    
    -- 获取第一个候选词
    local function get_first_candidate()
        for cand in input:iter() do
            AuxFilter.ftext = cand.type == "Shadow" or cand.type == "simplified" 
                             and cand:get_genuine().text or cand.text
            return cand
        end
    end
    
    -- 解析输入码
    local function parse_input_code()
        local auxcode = AuxFilter.inputCode:match(AuxFilter.trigger_key_pattern .. "(%a*)" .. AuxFilter.trigger_key_pattern)
        local funccode = AuxFilter.inputCode:match(AuxFilter.trigger_key_pattern .. "%a*" .. AuxFilter.trigger_key_pattern .. "+(%a*)")
        local ybmodif = funccode and funccode:match("s(%a+)")
        
        if ybmodif then
            branchmark = 2
            funccode = string.gsub(funccode, "s" .. ybmodif, "")
        end
        
        return auxcode, funccode, ybmodif
    end
    
    -- 计算偏移量和处理拼音
    local function process_offsets(firstcandi, funccode)
        AuxFilter.leftcompen = countSubstringOccurrences(funccode or "", "a")
        AuxFilter.rightcompen = countSubstringOccurrences(funccode or "", "d") + 
                               2 * countSubstringOccurrences(funccode or "", "f")
        
        local inputspls = split_pinyin(firstcandi.preedit)
        AuxFilter.ficompensate = utf8len(firstcandi.text)
        return inputspls
    end
    
    -- 确定断点位置
    local function find_break_point(inputspls, auxcode)
        local passnum = countSubstringOccurrences(AuxFilter.inputCode, AuxFilter.trigger_key) - 2
        local matchedmark = false
        
        for index, value in ipairs(inputspls) do
            local zi = utf8sub(AuxFilter.ftext, index, index)
            local best_value = best_match(AuxFilter.zi_to_yin[zi], value)
            local auxtab = AuxFilter.comb_code[value] or AuxFilter.comb_code[best_value] or {}
            
            if combmath(auxcode, auxtab) then
                AuxFilter.ficompensate = index
                matchedmark = true
                if passnum == 0 then break end
                passnum = passnum - 1
            end
        end
        
        if matchedmark then
            AuxFilter.ficompensate = AuxFilter.ficompensate - 1
        end
        
        return matchedmark
    end

    -- 主流程执行
    local firstcandi = get_first_candidate()
    if not firstcandi then return end
    local auxcode, funccode, ybmodif = parse_input_code()
    local inputspls = process_offsets(firstcandi, funccode)
    local matchedmark = find_break_point(inputspls, auxcode)
    
    -- 处理修音模式
    if branchmark == 2 then
        AuxFilter.notifiermark = 3
        local wrongyb = inputspls[AuxFilter.ficompensate + 1]
        inputspls[AuxFilter.ficompensate + 1] = ybmodif
        local inputcode2 = table.concat(inputspls, "")
        AuxFilter.ybmodifiedcode = AuxFilter.transdcodei .. inputcode2 .. AuxFilter.trigger_key
        AuxFilter.removetransdInput = inputcode2:sub(1, -2)
        yield(Candidate(firstcandi.type, firstcandi._start, firstcandi._start, "", wrongyb .. "->" .. ybmodif))
    
    -- 处理断句模式
    elseif branchmark == 1 then
        local finalcandi = candisub:new(firstcandi, AuxFilter.ficompensate)
        finalcandi.comment = matchedmark and "" or "辅码无匹配"
        AuxFilter.yield_candisub(finalcandi)
    end
end

--- 特殊预处理
local function transform_input_code(inputcode)
    local php = AuxFilter.ph_pattern  -- 已处理过的 pattern-safe ph
    local ph = AuxFilter.ph           -- 原始分隔符
    -- local sg = AuxFilter.switch_single_char
    local trigger = AuxFilter.trigger_key

    local pattern = "^([^" .. php  .. AuxFilter.trigger_key_pattern.."]+)" .. php .. "([^" .. php ..AuxFilter.trigger_key_pattern.. "]+)$"
    if inputcode:match(pattern) then
        return inputcode:gsub(pattern, "%1" .. trigger .. ph .. ph .. "%2")
    else
        return inputcode
    end
end

-- 使用示例
function AuxFilter.Update_codes(ctx)
    local context = ctx
    --- 预处理输入码
    AuxFilter.inputCode = context.input --输入码
    AuxFilter.inputCode = transform_input_code(AuxFilter.inputCode)
    -- logdic(AuxFilter.inputCode)

    -- log.info("输入码",AuxFilter.inputCode)
    AuxFilter.precode = context:get_preedit().text --预处理码 
    AuxFilter.precode = transform_input_code(AuxFilter.precode)
    -- logdic(context:get_script_text())
    -- logdic(AuxFilter.precode)
    AuxFilter.removeAuxInput = AuxFilter.inputCode:match("^(%a+)" .. AuxFilter.trigger_key_pattern.."-")  or ""--纯输入引导键前的部分
    -- log.info("引导键前的输入",AuxFilter.removeAuxInput)
    AuxFilter.removeAuxprecode = AuxFilter.precode:match("^([^" .. AuxFilter.trigger_key_pattern .. "]*)" .. AuxFilter.trigger_key_pattern.."-") or "" --去除辅码后的pre
    -- log.info("引导键前的预处理",AuxFilter.removeAuxprecode)
    -- logdic("引导键前的预处理" .. AuxFilter.removeAuxprecode)
    AuxFilter.removetransdInput= AuxFilter.removeAuxprecode:match("^[^a-z]*(%a*)") or ""  --翻译过后引导键前的未翻译部分  
    -- logdic("引导键前的未翻译"..AuxFilter.removetransdInput) 
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
    -- 只替换最后一个 switch_key
    ctx.input = ctx.input:gsub(AuxFilter.switch_key .. "$", "")
    AuxFilter.Update_codes(ctx)
    -- logdic(AuxFilter.inputCode)
end
function AuxFilter.func(input, env) 
    AuxFilter.env = env
    -- local pyrdb = ReverseDb("build/rime_ice.reverse.bin")
    -- local a = pyrdb:lookup("ni")
    -- logdic(a)

    -- log.info("输入码",AuxFilter.inputCode)
    -- logdic("出發")
    AuxFilter.notifiermark = -1
    AuxFilter.yieldset = {}
    AuxFilter.yieldrawset = {}
    AuxFilter.leftcompen = 0
    AuxFilter.rightcompen = 0
    AuxFilter.skipc = 0
    AuxFilter.counter = 0
    AuxFilter.prelen = nil -- 第一個上屏詞的長度 用於偏離計算 
    AuxFilter.single_flag = AuxFilter.single_flag or false --標記篩選類型是哪個
    AuxFilter.dupc = 1 --复制次数
    AuxFilter.transor = false
    local ctx = env.engine.context
    AuxFilter.Update_codes(ctx)
    if AuxFilter.removetransdInput ~= "" then
            AuxFilter.transedtext = nil -- 缓存再处理后的文字，迫不得已，不染
    end
    -- 分流
    local pattern_main1 = "^%a+" .. AuxFilter.trigger_key_pattern ..'[%a' .. AuxFilter.ph .. ']*$'  --辅筛分支的正则
    local pattern_singlechar_switch = "^%a+" .. AuxFilter.trigger_key_pattern ..'%a*' .. AuxFilter.switch_key ..'$'  -- 单字输入切换分支的正则
    local pattern_long = "^%a+" ..AuxFilter.trigger_key_pattern .. "%a*" .. AuxFilter.trigger_key_pattern .."+%a*$" --长句修改分支的正则
    if string.match(AuxFilter.inputCode,pattern_main1)then
        -- logdic("进入分支1"..AuxFilter.inputCode)
        local composition = env.engine.context.composition
        if(not composition:empty()) then
            local segment = composition:back()
            if AuxFilter.single_flag then 
                segment.prompt = "单字筛选分支"
            end
        end
        AuxFilter.notifiermark = 1
        -- logdic("进入分支1" .. AuxFilter.inputCode)
        AuxFilter.main1(input,env)
    elseif string.match(AuxFilter.inputCode,pattern_singlechar_switch) then
        -- logdic("进入分支3"..AuxFilter.inputCode)
        switch_single_char(env.engine.context)
        AuxFilter.notifiermark = 1
        AuxFilter.main1(input,env)
    elseif string.match(AuxFilter.inputCode,pattern_long) then
        AuxFilter.last_fist_commit = nil
        AuxFilter.longcandimodify(input,env) 
        -- logdic("进入分支2"..AuxFilter.inputCode)    
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