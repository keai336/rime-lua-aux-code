local AuxFilter = {}
local log = require ('log')
local http = require("simplehttp")
log.outfile = "a.txt"
http.TIMEOUT = 0.2
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
    -- log.info("ini",111)
    -- log.info("** AuxCode filter", env.name_space)
    local engine = env.engine
    AuxFilter.memory = Memory(env.engine, env.engine.schema)
    local defaultuserprefer = {path="ZRM_Aux-code",showor="true",trigger=";",matchmode="s"}
    local keys = {"path", "showor","trigger", "matchmode"}
    local userprefer = string.gmatch(env.name_space,"([^@]+)")
    local counter0 = 0
    for item in userprefer do
        counter0 = counter0+1
        -- log.info(item)
        if item then
            defaultuserprefer[keys[counter0]] = item
        end
    end
    -- log.info(defaultuserprefer)
    if AuxFilter.aux_code == nil then
        AuxFilter.readAuxTxt(defaultuserprefer["path"])
    end
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
local xn_sp2qp_table = {["aa"]="a",["ai"]="ai",["an"]="an",["ah"]="ang",["ao"]="ao",["ba"]="ba",["bd"]="bai",["bj"]="ban",["bh"]="bang",["bc"]="bao",["bw"]="bei",["bf"]="ben",["bg"]="beng",["bi"]="bi",["bx"]="bia",["bm"]="bian",["bl"]="biang",["bn"]="biao",["bp"]="bie",["bb"]="bin",["bk"]="bing",["bo"]="bo",["bu"]="bu",["ca"]="ca",["cd"]="cai",["cj"]="can",["ch"]="cang",["cc"]="cao",["ce"]="ce",["cw"]="cei",["cf"]="cen",["cg"]="ceng",["ia"]="cha",["id"]="chai",["ij"]="chan",["ih"]="chang",["ic"]="chao",["ie"]="che",["if"]="chen",["ig"]="cheng",["ii"]="chi",["is"]="chong",["iz"]="chou",["iu"]="chu",["ix"]="chua",["ik"]="chuai",["ir"]="chuan",["il"]="chuang",["iv"]="chui",["iy"]="chun",["io"]="chuo",["ci"]="ci",["cs"]="cong",["cz"]="cou",["cu"]="cu",["cr"]="cuan",["cv"]="cui",["cy"]="cun",["co"]="cuo",["da"]="da",["dd"]="dai",["dj"]="dan",["dh"]="dang",["dc"]="dao",["de"]="de",["dw"]="dei",["df"]="den",["dg"]="deng",["di"]="di",["dx"]="dia",["dm"]="dian",["dn"]="diao",["dp"]="die",["db"]="din",["dk"]="ding",["dq"]="diu",["ds"]="dong",["dz"]="dou",["du"]="du",["dr"]="duan",["dv"]="dui",["dy"]="dun",["do"]="duo",["ee"]="e",["ei"]="ei",["en"]="en",["eg"]="eng",["er"]="er",["fa"]="fa",["fj"]="fan",["fh"]="fang",["fw"]="fei",["ff"]="fen",["fg"]="feng",["fn"]="fiao",["fo"]="fo",["fs"]="fong",["fz"]="fou",["fu"]="fu",["ga"]="ga",["gd"]="gai",["gj"]="gan",["gh"]="gang",["gc"]="gao",["ge"]="ge",["gw"]="gei",["gf"]="gen",["gg"]="geng",["gs"]="gong",["gz"]="gou",["gu"]="gu",["gx"]="gua",["gk"]="guai",["gr"]="guan",["gl"]="guang",["gv"]="gui",["gy"]="gun",["go"]="guo",["ha"]="ha",["hd"]="hai",["hj"]="han",["hh"]="hang",["hc"]="hao",["he"]="he",["hw"]="hei",["hf"]="hen",["hg"]="heng",["hm"]="hm",["hq"]="hng",["hs"]="hong",["hz"]="hou",["hu"]="hu",["hx"]="hua",["hk"]="huai",["hr"]="huan",["hl"]="huang",["hv"]="hui",["hy"]="hun",["ho"]="huo",["ji"]="ji",["jx"]="jia",["jm"]="jian",["jl"]="jiang",["jn"]="jiao",["jp"]="jie",["jb"]="jin",["jk"]="jing",["js"]="jiong",["jq"]="jiu",["ju"]="ju",["jr"]="juan",["jt"]="jue",["jy"]="jun",["ka"]="ka",["kd"]="kai",["kj"]="kan",["kh"]="kang",["kc"]="kao",["ke"]="ke",["kw"]="kei",["kf"]="ken",["kg"]="keng",["ks"]="kong",["kz"]="kou",["ku"]="ku",["kx"]="kua",["kk"]="kuai",["kr"]="kuan",["kl"]="kuang",["kv"]="kui",["ky"]="kun",["ko"]="kuo",["la"]="la",["ld"]="lai",["lj"]="lan",["lh"]="lang",["lc"]="lao",["le"]="le",["lw"]="lei",["lg"]="leng",["li"]="li",["lx"]="lia",["lm"]="lian",["ll"]="liang",["ln"]="liao",["lp"]="lie",["lb"]="lin",["lk"]="ling",["lq"]="liu",["lo"]="lo",["ls"]="long",["lz"]="lou",["lu"]="lu",["lr"]="luan",["lt"]="lue",["ly"]="lun",["lo"]="luo",["lv"]="lv",["am"]="m",["ma"]="ma",["md"]="mai",["mj"]="man",["mh"]="mang",["mc"]="mao",["me"]="me",["mw"]="mei",["mf"]="men",["mg"]="meng",["mi"]="mi",["mm"]="mian",["mn"]="miao",["mp"]="mie",["mb"]="min",["mk"]="ming",["mq"]="miu",["mo"]="mo",["mz"]="mou",["mu"]="mu",["na"]="na",["nd"]="nai",["nj"]="nan",["nh"]="nang",["nc"]="nao",["ne"]="ne",["nw"]="nei",["nf"]="nen",["ng"]="neng",["aq"]="ng",["ni"]="ni",["nx"]="nia",["nm"]="nian",["nl"]="niang",["nn"]="niao",["np"]="nie",["nb"]="nin",["nk"]="ning",["nq"]="niu",["ns"]="nong",["nz"]="nou",["nu"]="nu",["nr"]="nuan",["nt"]="nue",["ny"]="nun",["no"]="nuo",["nv"]="nv",["oo"]="o",["ou"]="ou",["pa"]="pa",["pd"]="pai",["pj"]="pan",["ph"]="pang",["pc"]="pao",["pw"]="pei",["pf"]="pen",["pg"]="peng",["pi"]="pi",["px"]="pia",["pm"]="pian",["pn"]="piao",["pp"]="pie",["pb"]="pin",["pk"]="ping",["po"]="po",["pz"]="pou",["pu"]="pu",["qi"]="qi",["qx"]="qia",["qm"]="qian",["ql"]="qiang",["qn"]="qiao",["qp"]="qie",["qb"]="qin",["qk"]="qing",["qs"]="qiong",["qq"]="qiu",["qu"]="qu",["qr"]="quan",["qt"]="que",["qy"]="qun",["rj"]="ran",["rh"]="rang",["rc"]="rao",["re"]="re",["rf"]="ren",["rg"]="reng",["ri"]="ri",["rs"]="rong",["rz"]="rou",["ru"]="ru",["rx"]="rua",["rr"]="ruan",["rv"]="rui",["ry"]="run",["ro"]="ruo",["sa"]="sa",["sd"]="sai",["sj"]="san",["sh"]="sang",["sc"]="sao",["se"]="se",["sw"]="sei",["sf"]="sen",["sg"]="seng",["ua"]="sha",["ud"]="shai",["uj"]="shan",["uh"]="shang",["uc"]="shao",["ue"]="she",["uw"]="shei",["uf"]="shen",["ug"]="sheng",["ui"]="shi",["uz"]="shou",["uu"]="shu",["ux"]="shua",["uk"]="shuai",["ur"]="shuan",["ul"]="shuang",["uv"]="shui",["uy"]="shun",["uo"]="shuo",["si"]="si",["ss"]="song",["sz"]="sou",["su"]="su",["sr"]="suan",["sv"]="sui",["sy"]="sun",["so"]="suo",["ta"]="ta",["td"]="tai",["tj"]="tan",["th"]="tang",["tc"]="tao",["te"]="te",["tw"]="tei",["tg"]="teng",["ti"]="ti",["tm"]="tian",["tn"]="tiao",["tp"]="tie",["tk"]="ting",["ts"]="tong",["tz"]="tou",["tu"]="tu",["tr"]="tuan",["tv"]="tui",["ty"]="tun",["to"]="tuo",["wa"]="wa",["wd"]="wai",["wj"]="wan",["wh"]="wang",["ww"]="wei",["wf"]="wen",["wg"]="weng",["wo"]="wo",["ws"]="wong",["wu"]="wu",["xi"]="xi",["xx"]="xia",["xm"]="xian",["xl"]="xiang",["xn"]="xiao",["xp"]="xie",["xb"]="xin",["xk"]="xing",["xs"]="xiong",["xq"]="xiu",["xu"]="xu",["xr"]="xuan",["xt"]="xue",["xy"]="xun",["ya"]="ya",["yd"]="yai",["yj"]="yan",["yh"]="yang",["yc"]="yao",["ye"]="ye",["yi"]="yi",["yb"]="yin",["yk"]="ying",["yo"]="yo",["ys"]="yong",["yz"]="you",["yu"]="yu",["yr"]="yuan",["yt"]="yue",["yy"]="yun",["za"]="za",["zd"]="zai",["zj"]="zan",["zh"]="zang",["zc"]="zao",["ze"]="ze",["zw"]="zei",["zf"]="zen",["zg"]="zeng",["va"]="zha",["vd"]="zhai",["vj"]="zhan",["vh"]="zhang",["vc"]="zhao",["ve"]="zhe",["vw"]="zhei",["vf"]="zhen",["vg"]="zheng",["vi"]="zhi",["vs"]="zhong",["vz"]="zhou",["vu"]="zhu",["vx"]="zhua",["vk"]="zhuai",["vr"]="zhuan",["vl"]="zhuang",["vv"]="zhui",["vy"]="zhun",["vo"]="zhuo",["zi"]="zi",["zs"]="zong",["zz"]="zou",["zu"]="zu",["zr"]="zuan",["zv"]="zui",["zy"]="zun",["zo"]="zuo"}


local function xh_sp_code_2_qp(input)
   local result_table = {}
   for i = 1, #input, 2 do
      local pair = input:sub(i, i + 1)
      if i + 1 > #input then
         pair = input:sub(i)
      end
      table.insert(result_table, xn_sp2qp_table[pair] or pair)
   end
   return table.concat(result_table, " ")
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
        ctx.input = AuxFilter.removeAuxInput
        AuxFilter.ybtrans() 
        if AuxFilter.removetransdInput ~= "" then
            -- 給詞尾自動添加分隔符，上面的 re.match 會把分隔符刪掉
            ctx.input = ctx.input .. AuxFilter.trigger_key
        else
            -- 剩下的直接上屏
            -- log.info(AuxFilter.transdcode,AuxFilter.removeAuxInput)
            ctx:commit()
            ctx.commit_history:pop_back()
            local commit = ctx.commit_history:back()
            -- logdic(commit.text .. "|" .. commit.type .. "|" .. AuxFilter.removeAuxInput .. "|" .. AuxFilter.transdcode .. "|" .. xh_sp_code_2_qp(AuxFilter.removeAuxInput))
            --- 只记录词
            local entry = DictEntry()
            entry.text = AuxFilter.transdcode:gsub("‸+$", "")
            -- logdic(entry.text)
            entry.custom_code = xh_sp_code_2_qp(AuxFilter.removeAuxInput) .. " "
            AuxFilter.memory:start_session()
            local r = AuxFilter.memory:update_userdict(entry, 1, "")
            AuxFilter.memory:finish_session()
            -- if utf8len(AuxFilter.transdcode)>1 then
            --     -- logdic(AuxFilter.transdcode .. "," .. AuxFilter.removeAuxInput) 
  
            -- end

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
    local serverpath = userPath .. "/server"
    -- local execute = os.execute("cd " .. serverpath .. " && server.exe")
    -- if execute ~= 0 then
    --     log.info("启动本地服务失败")
    -- end
    local file = io.open(fileAbsolutePath, "r") or io.open(userPath .. defaultFile, "r")
    if not file then
        error("Unable to open auxiliary code file.")
        return {}
    end

    local auxCodes = {} -- 字 ：{全辅码}
    local mixedCodes= {}  --{音码:{可匹配的辅码集}}
    for line in file:lines() do
        line = line:match("[^\r\n]+") -- 去掉換行符，不然 value 是帶著 \n 的
        -- local key, value = line:match("([^=]+)=(.+)") -- 分割 = 左右的變數
        local zi,yb,fu = string.match(line,"([^\t]+)\t([^\t]+)\t([^\t]+)")
        -- local key = zi
        -- local value = xk
        -- log.info(key,value)
        local fuset = two_char_combinations(fu)
        if zi and fu and yb then
            -- auxCodes 的逻辑不变
            auxCodes[zi] = auxCodes[zi] or {}  
            table.insert(auxCodes[zi], fu)
            --加入mixedcodes的逻辑  这里只考虑到音码是两位,且完整辅码是两位
            mixedCodes[yb] = mixedCodes[yb] or {}
            for k,v in ipairs(fuset) do
                mixedCodes[yb][v] = mixedCodes[yb][v] or {}
                table.insert(mixedCodes[yb][v],zi)
            end

        end
    end
    AuxFilter.aux_code = auxCodes
    AuxFilter.comb_code = mixedCodes
    -- log.info(#mixedCodes)
    file:close()
    log.info(serverpath)
    os.execute('taskkill /IM server.exe /F')
    os.execute("cd " .. serverpath .. " && cmd /c start server.exe")
    return auxCodes
end

-- 定义函数来获取表的所有值
local function table_values(tbl)
    local values = {}
    for _, value in pairs(tbl) do
        table.insert(values, value)
    end
    return values
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


-- 定义函数来将字符串两两分割  获取 音节
local function splitToPairs(str)
    local result = {}
    for i = 1, #str, 2 do
        local pair = str:sub(i, i+1) -- 取出两个字符
        table.insert(result, pair)   -- 将两个字符插入到结果表中
    end
    return result
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
    -- local x1 = fullAux[1]:find(auxStr:sub(1, 1)) or -1
    -- local x2 = fullAux[2]:find(auxStr:sub(2, 2)) or -2
    -- local xmark1 = fullAux[1][x2]==auxStr:sub(1,1)
    -- local xmark2 = fullAux[2][x1]==auxStr:sub(2,2)
    -- local vgpipw = firstKeyMatched and secondKeyMatched 
    -- local fjpipw = secondKeymatched and fiestKeymatched
    -- if AuxFilter.matchmode==1 then
    --     return vgpipw and (xmark1 or xmark2)
    -- end
    -- return vgpipw or fjpipw
    return mark
end
-- 返回指定长度的候选
function AuxFilter.yield_candisub(cand,len)
    local candset = utf8sub(cand.text,1,len)
    local _end = 2*len
    local fiend = cand._start+_end
    if fiend>cand._end then
        fiend = cand._end
    end
    -- local finalcandi = Candidate(cand.type,cand._start,fiend,candset,cand.comment)
    local finalcandi = Candidate(cand.type,cand._start,fiend,candset,cand.comment)
    if AuxFilter.yieldset[finalcandi.text]~=nil then
        return    
    end
    AuxFilter.yieldset[finalcandi.text] = true
    if AuxFilter.skipc<=0 then
        yield(finalcandi)
        
    else
        AuxFilter.skipc=AuxFilter.skipc-1
    end

end

-- 輔助函數，用於獲取表格的所有鍵
local function table_keys(t)
    local keys = {}
    for key, _ in pairs(t) do
        table.insert(keys, key)
    end
    return keys
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
                -- log.info(aux,tab[aux],tab[aux:reverse()],table.concat(table_keys(tab),"-"))
            end
        end
    elseif AuxFilter.matchmode==1 then
        if #aux~=0 then
            if not boolaux(tab[aux]) then
                mark = false
                -- log.info(aux,tab[aux],table.concat(table_keys(tab),"-"))
            end
        end
    end


    -- log.info(aux,mark)
return mark
end
local function main_main(env,cand)
    local auxCodes = AuxFilter.aux_code[cand.text] -- 僅單字非 nil
    local fullAuxCodes = AuxFilter.fullAux(env, cand.text)

    -- 查看 auxCodes
    -- log.info(cand.text, #auxCodes)
    -- for i, cl in ipairs(auxCodes) do
    --     log.info(i, table.concat(cl, ',', 1, #cl))
    -- end

    -- 給待選項加上輔助碼提示
    if AuxFilter.show_aux_notice and auxCodes and #auxCodes > 0 then
        local codeComment = table.concat(auxCodes, ',')
        -- 處理 simplifier
        if cand:get_dynamic_type() == "Shadow" then
            local shadowText = cand.text
            local shadowComment = cand.comment
            local originalCand = cand:get_genuine()
            cand = ShadowCandidate(originalCand, originalCand.type, shadowText,
                originalCand.comment .. shadowComment .. '(' .. codeComment .. ')')
        else
            cand.comment = '(' .. codeComment .. ')'
        end
    end

    -- 過濾輔助碼
    if #(AuxFilter.auxStr) == 0 then
        -- 沒有輔助碼、不需篩選，直接返回待選項
        if AuxFilter.counter==0 then
            local compensate = cand._end - cand._start
            AuxFilter.ficompensate = compensate/2 - AuxFilter.leftcompen + AuxFilter.rightcompen
            if AuxFilter.ficompensate<=0 then
                AuxFilter.ficompensate = 1
            end
        end
        AuxFilter.counter=AuxFilter.counter+1
        AuxFilter.yield_candisub(cand,AuxFilter.ficompensate)
    elseif #(AuxFilter.auxStr) > 0 and fullAuxCodes and  AuxFilter.match(fullAuxCodes, AuxFilter.auxStr) then
        -- 匹配到辅助码的待选项，直接插入到候选框中( 获得靠前的位置 )
        if AuxFilter.counter==0 then
            local compensate = cand._end - cand._start
            AuxFilter.ficompensate = compensate/2 - AuxFilter.leftcompen + AuxFilter.rightcompen
            if AuxFilter.ficompensate<=0 then
                AuxFilter.ficompensate = 1
            end
        end
        AuxFilter.counter = AuxFilter.counter+1
        AuxFilter.yield_candisub(cand,AuxFilter.ficompensate)
    else
        -- 待选项字词 没有 匹配到当前的辅助码，插入到列表中，最后插入到候选框里( 获得靠后的位置 )
        -- table.insert(insertLater, cand)
        -- 更新逻辑：没有匹配上就不出现再候选框里，提升性能
    end
end
--- 分支一 原来的功能
function AuxFilter.main1(input,env)
    env.notifiermark = 1  --辅筛情况下的 选词后的逻辑标记 变为 1
    -- 分割部分正式開始
    AuxFilter.auxStr = ''
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
    -- local insertLater = {}

    -- 遍歷每一個待選項
    AuxFilter.counter = 0 -- 计数返回候选数量
    local firstcandi = ""      -- 第一个候选也就是最长的那个
    local index=0  --为了获取第一个候选的判断变量
    for cand in input:iter() do
        -- log.info(cand.text,ficompensate)
        index = index+1
        --第一个候选词 额外逻辑
        if index==1 then
            if #(AuxFilter.firstcandipre)~=0 then
                for _, value in ipairs(AuxFilter.firstcandipre) do
                    value._start = cand._start
                    value._end  = cand._start+2*utf8len(value.text)
                    main_main(env,value)
                end
                
            end
            main_main(env,cand)   
            break
        end

    end
    for value in input:iter() do
        main_main(env,value)
    end
    --如果辅筛没筛出来,提示你进行辅断
    if AuxFilter.counter==0 then
        local inputspls  = splitToPairs(AuxFilter.removetransdInput) --未翻译的音码集合
        -- log.info("inputls")
        local matchybtab = {} --辅码可以组合的未翻译的音码的集合
        local firstcandtext = firstcandi.text
        -- log.info(auxStr)
        for index, value in ipairs(inputspls) do
            -- log.info(index,value)
            local auxtab = AuxFilter.comb_code[value]
            -- log.info(auxtab)
            if combmath(AuxFilter.auxStr,auxtab) then
                -- log.info("111")
                table.insert(matchybtab,tostring(index).."." .. utf8sub(firstcandtext,index,index))
            end
        end
        -- log.info(111)
        local commentfirst =  "无匹配"
        if #matchybtab~=0 then
            commentfirst = table.concat(matchybtab,"--")
        end
            -- log.info(firstcandi.text)
        firstcandi.comment = commentfirst
        -- log.info(firstcandi.text)
        -- log.info("comment" ,commentfirst)
        yield(firstcandi)
    end
end



--- 无触发分支
function AuxFilter.defaultmain(input)
    -- log.info(1)
    for cand in input:iter() do
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
        firstcandi = cand
        break
    end
    if #(AuxFilter.firstcandipre) ~=0 then
        local candi = table.remove(AuxFilter.firstcandipre)
        candi._start = firstcandi._start
        candi._end  = firstcandi._end
        firstcandi = candi
    end
    local auxcode = AuxFilter.inputCode:match(AuxFilter.trigger_key_pattern .. "(%a*)" .. AuxFilter.trigger_key_pattern) --辅码部分
    -- log.info("auxcode",auxcode)
    local funccode = AuxFilter.inputCode:match(AuxFilter.trigger_key_pattern .. "%a*" .. AuxFilter.trigger_key_pattern .. "+(%a*)") --功能码部分
    -- log.info("fucncode",funccode)
    local ybmodif = funccode:match("s(%a%a)") --功能码部分捕获的修音的音码
    -- local yyciif = countSubstringOccurrences(funccode,"y")
    -- local pinyin = firstcandi.preedit:gsub("%s+", "")
    -- if  yyciif==1 then
    --     -- local url = make_url(pinyin, 0, 5)
    --     local url = "http://localhost:6234/pre/".. pinyin
    --     http.request(url)
    --     return
    --     -- log.info(reply)

    --     end   
    -- if yyciif==2 then
    --     local url = "http://localhost:6234/result/".. pinyin
    --     local reply = http.request(url)
    --     if reply~="" then
    --         for word in string.gmatch(reply, "[^@]+") do 
    --             yield(Candidate("simple", firstcandi._start, firstcandi._end, word, "(百度云拼音)"))
    --         end
    --     end
    --     return

        

        
    -- end
        
    if ybmodif then 
        --进入修音分支处理
        branchmark=2
        funccode = string.gsub(funccode,"s" .. ybmodif,"") --减掉修音部分的功能码,为后续统计偏移做准备
    end
    -- log.info("音码",ybmodif)
    -- log.info("funccode",funccode)
    local leftcompen = countSubstringOccurrences(funccode,"a") --左偏移量
    local rightcompen = countSubstringOccurrences(funccode,"d") + 2 * countSubstringOccurrences(funccode,"f") -- 右偏移量
    local inputspls  = splitToPairs(AuxFilter.removetransdInput) --把未翻译的音码拆成单字音码列表  {音码1,音码2}
    local compensate = utf8len(firstcandi.text) --初始化偏移量  默认在断点尾部
    local passnum = countSubstringOccurrences(AuxFilter.inputCode,AuxFilter.trigger_key) -2  --计算跳过匹配数  功能码中 ; 的作用
    -- log.info(inputspls[1])
    --确定最终断点位置
    local matchedmark = false  --整句辅码是否有有效配对
    for index, value in ipairs(inputspls) do
        local auxtab = AuxFilter.comb_code[value]
        if combmath(auxcode,auxtab) then
            compensate = index
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
    compensate = compensate + rightcompen - leftcompen
    if matchedmark then
       compensate = compensate -1  --减1是要断在作用词之前  
    end
  
    --如果前面没字就上一个
    if compensate<=0 then
        compensate =1
    end

    --在断点处修音逻辑
    if branchmark==2 then
        env.notifiermark = 3 --修音模式下,选词后的逻辑的标志变为3
        local wrongyb = inputspls[compensate]
        inputspls[compensate] = ybmodif
        local inputcode2 = table.concat(inputspls,"")  --修改后的未翻译音码连接为字符串
        -- log.info(inputcode2)
        AuxFilter.ybmodifiedcode = AuxFilter.transdcodei .. inputcode2 .. AuxFilter.trigger_key  --修改后的音码 + 引导键

        AuxFilter.removetransdInput = inputcode2:sub(1,-2)
        AuxFilter.ybtrans()
        yield(Candidate(firstcandi.type,firstcandi._start,firstcandi._start,"",wrongyb .."->" .. ybmodif))  --"确定"  候选项
    
    --在断点处断句逻辑
    elseif branchmark==1 then
        local comment = ""
    local finalcandi = AuxFilter.yield_candisub(firstcandi,compensate)
    if not matchedmark then
        comment = "辅码无匹配"
    end
    finalcandi.comment = comment
    yield(finalcandi)
    end
end





--- 输入单字分支  对于诗文类或许有用
function AuxFilter.singlechar(input,env)
    env.notifiermark = 4 --单字分支下选词后逻辑 的标记
    local  inputcode =env.engine.context.input
    local  ybxkinputcode = inputcode:sub(2,-1)
    local  ybcode = ""
    local xkcode = ""
    if #inputcode==3 then  -- 引导键+两位音码   返回音码 下的所有单字并注释形码
        ybcode = inputcode:sub(2,-1) 
        local ci = AuxFilter.comb_code[ybcode]
        local finalkey = {}
        for k,v in pairs(ci) do 
            if #k==2 then 
                for i,v in pairs(v) do
                    finalkey[v] = k
                end
            end
        end
        for k,v in pairs(finalkey) do
            if AuxFilter.show_aux_notice then
                yield(Candidate("single",1,#inputcode,k,v))
            else
                yield(Candidate("single",1,#inputcode,k,""))
            end
            
        end
        return

    else                    --引导键 + 两位音码 +形码   返回 音形共同定位下的字 并注释形码
        ybcode = ybxkinputcode:sub(1,2)
        xkcode = ybxkinputcode:sub(3,-1)
        -- log.info(xkcode)
        local ci = AuxFilter.comb_code[ybcode]
        if not ci then
            return
        end
        if AuxFilter.matchmode==0 then
            ci = AuxFilter.comb_code[ybcode][xkcode] or AuxFilter.comb_code[ybcode][xkcode:reverse()]
        else 
            ci = AuxFilter.comb_code[ybcode][xkcode]
        end
        if ci then
        if table.size(ci) ~= 0 then
            for k,v in  pairs(ci) do
                local comment = AuxFilter.aux_code[v] or {}
                local comment = table.concat(comment,"-")
                if AuxFilter.show_aux_notice then 
                    yield(Candidate("single",1,#inputcode,v,comment))
                else
                    yield(Candidate("single",1,#inputcode,v,""))
                end
            end
        end
        else
        env.engine.context:clear()
        env.engine.context:push_input(inputcode:sub(1,3))
        -- env.engine.context.input = inputcode:sub(1,3)  --这是输入形码无效后回退到没有形码 ,保留引导键和音码 
        return
        end
    end
end
------------------
-- filter 主函數 --
------------------
-- local function osget(inp)
--     local order = rime_api.get_user_data_dir() .. "/lua/" .. 'qkqq '.. inp
--     log.info(order)
--     local handle = io.popen(order)
--     local result = handle:read("*a")
--     handle:close()
--     return result
    
-- end

-- 定义提取键值对的函数
local function extractKeyValuePairs(input)
    -- 分割字符串的辅助函数
    local function split(str, delimiter)
        local result = {}
        for match in (str .. delimiter):gmatch("(.-)" .. delimiter) do
            table.insert(result, match)
        end
        return result
    end

    local entries = split(input, "@")
    local keyValuePairs = {}

    for _, entry in ipairs(entries) do
        local key, value = entry:match("([^$]+)%$(.+)")
        if key and value then
            table.insert(keyValuePairs, {key = key, value = value})
        end
    end

    return keyValuePairs
end



function AuxFilter.ybtrans()
    local l = #AuxFilter.removetransdInput
    if l<=4 then
        return
    end
    local vf,yu = math.modf(l/2)
    if yu~=0 then
        local url = "http://127.0.0.1:6790/pre/".. AuxFilter.removetransdInput
        -- logdic("云拼音请求"..AuxFilter.removetransdInput)
        http.request(url)
        -- osget(AuxFilter.removetransdInput)
        return
    else
        local url = "http://127.0.0.1:6790/result/".. AuxFilter.removetransdInput
        -- logdic("云拼音请求"..AuxFilter.removetransdInput)
        local reply = http.request(url)
        if reply~="" then
            for _,word in ipairs(extractKeyValuePairs(reply)) do 
                table.insert(AuxFilter.firstcandipre,Candidate("simple", 0, l, word.key, word.value))
            end
        end
        return
    end
end


function AuxFilter.func(input, env)
    env.notifiermark = -1
    AuxFilter.firstcandipre = {}
    AuxFilter.yieldset = {}
    local context = env.engine.context
    --- 预处理输入码
    AuxFilter.inputCode = context.input --输入码
    -- log.info("输入码",AuxFilter.inputCode)
    AuxFilter.precode = context:get_preedit().text --预处理码 
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
    -- 云词处理
    AuxFilter.ybtrans()
    -- log.info(#(AuxFilter.firstcandipre))
    -- 分流
    local pattern_main1 = "^%a+" .. AuxFilter.trigger_key_pattern ..'%a*$'  --辅筛分支的正则
    local pattern_long = "^%a+" ..AuxFilter.trigger_key_pattern .. "%a*" .. AuxFilter.trigger_key_pattern .."+%a*$" --长句修改分支的正则
    local pattern_singlechar = "^" .. AuxFilter.trigger_key_pattern .. "%a%a%a?%a?$"  -- 单字输入分支
    if string.match(AuxFilter.inputCode,pattern_main1)then
        -- log.info("进入分支1",AuxFilter.inputCode)
        AuxFilter.main1(input,env)
    elseif string.match(AuxFilter.inputCode,pattern_long) then
        AuxFilter.longcandimodify(input,env) 
        -- log.info("进入分支2",AuxFilter.inputCode)    
    elseif string.match(AuxFilter.inputCode,pattern_singlechar) then
        AuxFilter.singlechar(input,env)
        -- log.info("进入分支3",AuxFilter.inputCode)
    --都不匹配直接返回的分支
    else
        AuxFilter.defaultmain(input)
        end
    
end

function AuxFilter.fini(env)
    -- log.info("fini")
    env.notifier:disconnect()



     

end

return AuxFilter
