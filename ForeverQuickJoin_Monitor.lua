-- Forever QuickJoin Monitor Mode for WoW Forever 1.60.1
-- Integrated with ForeverQuickJoin v0.9.10 (release).
-- Group Listings: new server queries always require a player click.
-- LFG Chat: live public recruitment posts use activity filters only.
-- LookingForGroup auto-join uses the native chat API and respects
-- QuickJoin's existing chatAutoJoin preference and rate limits.
-- No timer triggers a protected Search(), whisper, or invite.
local ADDON = ...
local M = {}
ForeverQuickJoinMonitor = M

local active, awaitingResults, attached = false, false, false
local DB, scope, latestSearch, searchButton, mainWindow
local popup, indicator, context, contextWho, contextWhisper, intro, introNever
local themeDropdown, orbSpinner = nil, nil
local RenameSettingsLabel, ApplyMinimapLogo
local Start, UpdateIndicator, PositionPopup, PlayPopupIntro, ApplyTheme, ShowIntro, RefreshIntroLocale, MonitorLanguage
local orbSearchAttempt, orbSearchAt = false, 0
local header, activityText, subtext, roleText, descriptionText, queueText, freshnessText
local whisperButton, inviteButton, expandButton, rosterTitle, prevButton, nextButton, rosterPager, groupPager, contextCloseButton
local rosterRows, pending, seen, searchIDs, attempts = {}, {}, {}, {}, {}
local collectingResults = false
local Enqueue -- forward declaration: live chat handler enqueues after source validation
local dismissed = {} -- explicit X dismissals; chat dismissals survive manual refreshes
-- Contact status lasts for this play session only (no SavedVariables writes).
-- Track by normalized leader name across Group Listings and LFG Chat.
-- Dismissing a listing is independent of whispering the player.
local whisperedLeaders = {}

local CHAT_TTL = 600
local chatAlertAt = -100
local chatObserved, chatMatched = 0, 0
local wasGrouped = false
local prevGroupButton, nextGroupButton, selectedIndex = nil, nil, 1
local themedButtons={}
local ApplyButtonTheme, ApplyPanelTheme
local current, selectedName, pendingWho = nil, nil, nil
local whoZones = {}
local expanded, rosterOffset, verifiedAt = false, 0, nil
local lastUserSearchAt = 0
local SEARCH_FRESH_SECONDS = 300
local INTRO_VERSION = "monitor-mode-7"
local NOTIFY_DEDUP_SECONDS = 600
local MAX_QUEUE = 35
local ROW_COUNT = 7
local SOUND_ID = 568587 -- Blizzard PVPEnterQueue (search starts)
local STOP_SOUND_ID = 567420 -- Blizzard lfg_denied.ogg (user stops)
local function PlayNotifySound(fileID,kitID)
    -- 12.1+ clients expose per-play volumeOverride; request a 5% boost.
    -- WoW Forever builds without the API keep the original Blizzard SFX.
    if C_Sound and type(C_Sound.PlaySound)=="function" then
        local ok,played=pcall(C_Sound.PlaySound,kitID,"SFX",false,false,nil,1.05)
        if ok and played==true then return end
    end
    if type(PlaySoundFile)=="function" then
        PlaySoundFile(fileID,"SFX")
    elseif type(PlaySound)=="function" then
        PlaySound(kitID,"SFX")
    end
end

local function Now() return type(GetTime)=="function" and GetTime() or 0 end
local function Readable(v)
    if type(issecretvalue)=="function" and issecretvalue(v) then return nil end
    if type(canaccessvalue)=="function" and not canaccessvalue(v) then return nil end
    return v
end
local function Str(v)
    v=Readable(v)
    return type(v)=="string" and v~="" and v or nil
end
local function Num(v)
    v=Readable(v)
    return type(v)=="number" and v==v and v or nil
end
local function SafeName(v)
    v=Str(v)
    if not v or #v>100 or v:find('[|"\r\n]') or v:find('[%c]') then return nil end
    return v:match('^%s*(.-)%s*$')~="" and v or nil
end
local function LeaderKey(name)
    name=SafeName(name)
    return name and name:lower() or nil
end
local function Print(text)
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cff62c8efQuickJoin Monitor|r: "..tostring(text))
    end
end
local function Clean(text,max)
    text=Str(text) or ""
    if text:match("^|K[%w]+|k$") then return "Description protected by WoW" end
    text=text:gsub("[%c]"," "):gsub("|","||")
    if max and #text>max then text=text:sub(1,max-3).."..." end
    return text
end
local function Copy(tbl,depth)
    if type(tbl)~="table" or depth==0 then return tbl end
    local out={}
    for k,v in pairs(tbl) do
        if type(k)=="string" or type(k)=="number" then
            out[k]=type(v)=="table" and Copy(v,(depth or 4)-1) or v
        end
    end
    return out
end
local function InGroup()
    -- WoW Forever supports IsInGroup; fall back to group-size APIs.
    if type(IsInGroup)=="function" then
        local ok,value=pcall(IsInGroup)
        if ok and type(value)=="boolean" then return value end
    end
    if type(GetNumGroupMembers)=="function" then
        local ok,value=pcall(GetNumGroupMembers)
        if ok and type(value)=="number" then return value>0 end
    end
    return false
end
local function SetDB()
    if type(ForeverQuickJoinMonitorDB)~="table" then ForeverQuickJoinMonitorDB={} end
    DB=ForeverQuickJoinMonitorDB
    if type(DB.enabledOnSearch)~="boolean" then DB.enabledOnSearch=false end
    if type(DB.sound)~="boolean" then DB.sound=true end
    if type(DB.quietCombat)~="boolean" then DB.quietCombat=true end
    if type(DB.neverShowAnnouncements)~="boolean" then DB.neverShowAnnouncements=false end
    if type(DB.orbX)~="number" or math.abs(DB.orbX)>6000 then DB.orbX=310 end
    if type(DB.orbY)~="number" or math.abs(DB.orbY)>6000 then DB.orbY=-90 end
end

-- Main QuickJoin already attempts to join LookingForGroup on login. Monitor
-- checks that the character is actually subscribed when monitoring begins,
-- and retries at most twice per monitoring session if necessary. The existing
-- /qjchat autojoin off preference ALWAYS wins; this code never rejoins a
-- channel after the user explicitly opts out.
local lfgJoinLastAt, lfgJoinAttempts, lfgJoinStatus = -100000, 0, "not checked"
local lfgJoinNotBefore = 0
local function ChatAutoJoinOn()
    return type(ForeverQuickJoinDB)~="table" or ForeverQuickJoinDB.chatAutoJoin~=false
end
local function LFGJoined()
    if type(GetChannelName)~="function" then return false end
    local ok,id=pcall(GetChannelName,"LookingForGroup")
    id=ok and Readable(id) or nil
    return type(id)=="number" and id>0
end
local function TryAutoJoinLFG(userInitiated)
    if not ChatAutoJoinOn() then
        lfgJoinStatus="disabled in QuickJoin"
        return false
    end
    if LFGJoined() then
        lfgJoinStatus="joined"
        lfgJoinAttempts=0
        return true
    end
    if not userInitiated and (not active or not DB or not DB.enabledOnSearch) then return false end
    if not userInitiated and Now()<lfgJoinNotBefore then return false end
    if not userInitiated and (lfgJoinAttempts>=2 or Now()-lfgJoinLastAt<30) then return false end
    if type(JoinPermanentChannel)~="function" then
        lfgJoinStatus="client API unavailable"
        return false
    end
    if type(InCombatLockdown)=="function" and InCombatLockdown() then
        lfgJoinStatus="waiting for combat to end"
        return false
    end
    lfgJoinAttempts=lfgJoinAttempts+1
    lfgJoinLastAt=Now()
    local frameID=ChatFrame1 and type(ChatFrame1.GetID)=="function" and ChatFrame1:GetID() or nil
    -- Standard public channel subscription. Never sends a message to chat.
    local ok,result=pcall(JoinPermanentChannel,"LookingForGroup",nil,frameID)
    if not ok or result==false then
        lfgJoinStatus="channel join rejected"
        return false
    end
    lfgJoinStatus=LFGJoined() and "joined" or "join requested"
    return true
end

-- QuickJoin Monitor's own introduction strings. The main addon's locale
-- dictionary does not contain these feature-specific sentences.
local introText={
    enUS={
        title="FOREVER QUICKJOIN  |  WHAT'S NEW",
        hero="FIND GROUPS WHILE YOU PLAY",
        lead="Spend less time waiting in Group Finder and more time questing, farming, and exploring.",
        step1="1. ENABLE MONITOR MODE",
        step1Body="Open QuickJoin (/qj) and turn on Monitor Mode in Settings. Select your activities, use Advanced Filters to refine your search, and click Search.",
        step2="2. KEEP PLAYING",
        step2Body="QuickJoin monitors matching Group Listings and listens for new LFG Chat recruitment messages while you play. Left-click the icon to search Group Listings again.",
        step3="3. JOIN WHEN READY",
        step3Body="Click Whisper to Join, Invite, or view Details.",
        controls="ICON: LEFT-CLICK searches again  |  RIGHT-CLICK stops monitoring  |  DRAG moves",
        note="Group Listings need a manual search; public LFG Chat updates arrive automatically while monitoring.",
        never="Don't show this message again",
        ok="Got it!",
        help="What's New / Help",
        settings="Settings:",
    },
    frFR={
        title="FOREVER QUICKJOIN  |  NOUVEAUTÉS",
        hero="TROUVEZ UN GROUPE EN JOUANT",
        lead="Moins de temps à attendre, plus de temps pour les quêtes, la récolte et l’exploration.",
        step1="1. ACTIVER LE MODE SURVEILLANCE",
        step1Body="Ouvrez QuickJoin (/qj), puis activez le mode surveillance dans Paramètres. Choisissez vos activités, affinez la recherche avec les filtres avancés et cliquez sur Rechercher.",
        step2="2. CONTINUER À JOUER",
        step2Body="QuickJoin surveille les annonces correspondantes et écoute les nouvelles demandes de groupe dans le chat RdG pendant que vous jouez. Clic gauche sur l’icône : relancer la recherche d’annonces.",
        step3="3. REJOINDRE UN GROUPE",
        step3Body="Cliquez sur Chuchoter pour rejoindre, Inviter ou Détails.",
        controls="ICÔNE : CLIC GAUCHE : relancer la recherche  |  CLIC DROIT : arrêter la surveillance  |  GLISSER : déplacer",
        note="Les annonces nécessitent une recherche manuelle ; les messages du chat RdG arrivent automatiquement.",
        never="Ne plus afficher ce message",
        ok="Compris !",
        help="Nouveautés / Aide",
        settings="Paramètres :",
    },
    deDE={
        title="FOREVER QUICKJOIN  |  NEUIGKEITEN",
        hero="GRUPPEN SUCHEN, WÄHREND DU SPIELST",
        lead="Weniger Wartezeit, mehr Zeit für Quests, Farmen und Erkundungen.",
        step1="1. MONITORMODUS AKTIVIEREN",
        step1Body="Öffne QuickJoin (/qj) und aktiviere den Monitormodus unter Einstellungen. Wähle Aktivitäten, verfeinere die Suche mit Erweiterten Filtern und klicke auf Suchen.",
        step2="2. WEITERSPIELEN",
        step2Body="QuickJoin überwacht passende Gruppenangebote und neue LFG-Chat-Anzeigen während des Spielens. Linksklick auf das Symbol sucht erneut nach Gruppenangeboten.",
        step3="3. GRUPPE BEITRETEN",
        step3Body="Klicke auf Beitritt anflüstern, Einladen oder Details.",
        controls="SYMBOL: LINKSKLICK sucht erneut  |  RECHTSKLICK stoppt die Überwachung  |  ZIEHEN verschiebt",
        note="Gruppenangebote müssen manuell gesucht werden; der öffentliche LFG-Chat wird live überwacht.",
        never="Diese Meldung nicht mehr anzeigen",
        ok="Verstanden!",
        help="Neuigkeiten / Hilfe",
        settings="Einstellungen:",
    },
    esES={
        title="FOREVER QUICKJOIN  |  NOVEDADES",
        hero="BUSCA GRUPOS MIENTRAS JUEGAS",
        lead="Menos tiempo esperando y más tiempo haciendo misiones, consiguiendo recursos y explorando.",
        step1="1. ACTIVA EL MODO MONITOR",
        step1Body="Abre QuickJoin (/qj) y activa el modo Monitor en Ajustes. Elige las actividades, usa los Filtros avanzados para ajustar la búsqueda y pulsa Buscar.",
        step2="2. SIGUE JUGANDO",
        step2Body="QuickJoin supervisa anuncios compatibles y nuevos mensajes de reclutamiento del chat de grupos mientras juegas. Haz clic izquierdo para buscar anuncios otra vez.",
        step3="3. ÚNETE A UN GRUPO",
        step3Body="Pulsa Susurrar para unirte, Invitar o Detalles.",
        controls="ICONO: CLIC IZQUIERDO vuelve a buscar  |  DERECHO detiene la búsqueda  |  ARRASTRAR mueve",
        note="Los anuncios requieren búsqueda manual; los mensajes públicos del chat se reciben en directo.",
        never="No volver a mostrar este mensaje",
        ok="¡Entendido!",
        help="Novedades / Ayuda",
        settings="Ajustes:",
    },
    esMX={
        title="FOREVER QUICKJOIN  |  NOVEDADES",
        hero="BUSCA GRUPOS MIENTRAS JUEGAS",
        lead="Menos tiempo de espera y más tiempo para misiones, farmeo y exploración.",
        step1="1. ACTIVA EL MODO MONITOR",
        step1Body="Abre QuickJoin (/qj) y activa el modo Monitor en Configuración. Elige las actividades, usa los Filtros avanzados para afinar la búsqueda y haz clic en Buscar.",
        step2="2. SIGUE JUGANDO",
        step2Body="QuickJoin monitorea anuncios compatibles y nuevos mensajes de reclutamiento del chat de grupos mientras juegas. Haz clic izquierdo para buscar anuncios de nuevo.",
        step3="3. ÚNETE A UN GRUPO",
        step3Body="Haz clic en Susurrar para unirte, Invitar o Detalles.",
        controls="ÍCONO: CLIC IZQUIERDO vuelve a buscar  |  DERECHO detiene el monitoreo  |  ARRASTRAR mueve",
        note="Los anuncios necesitan búsqueda manual; el chat público se monitorea en tiempo real.",
        never="No volver a mostrar este mensaje",
        ok="¡Entendido!",
        help="Novedades / Ayuda",
        settings="Configuración:",
    },
    ptBR={
        title="FOREVER QUICKJOIN  |  NOVIDADES",
        hero="PROCURE GRUPOS ENQUANTO JOGA",
        lead="Menos tempo esperando, mais tempo fazendo missões, coletando recursos e explorando.",
        step1="1. ATIVE O MODO MONITOR",
        step1Body="Abra o QuickJoin (/qj) e ative o Modo Monitor em Configurações. Escolha as atividades, use os Filtros Avançados para refinar a busca e clique em Buscar.",
        step2="2. CONTINUE JOGANDO",
        step2Body="O QuickJoin acompanha os anúncios compatíveis e novas mensagens de recrutamento no chat de grupos enquanto você joga. Clique esquerdo para buscar anúncios novamente.",
        step3="3. ENTRE EM UM GRUPO",
        step3Body="Clique em Sussurrar para entrar, Convidar ou Detalhes.",
        controls="ÍCONE: CLIQUE ESQUERDO busca novamente  |  DIREITO para o monitoramento  |  ARRASTAR move",
        note="As listas precisam de busca manual; as mensagens do chat público chegam automaticamente.",
        never="Não mostrar esta mensagem novamente",
        ok="Entendi!",
        help="Novidades / Ajuda",
        settings="Configurações:",
    },
    ruRU={
        title="FOREVER QUICKJOIN  |  ЧТО НОВОГО",
        hero="ИЩИТЕ ГРУППЫ, НЕ ОТРЫВАЯСЬ ОТ ИГРЫ",
        lead="Меньше ожидания — больше времени на задания, фарм и исследования.",
        step1="1. ВКЛЮЧИТЕ РЕЖИМ МОНИТОРИНГА",
        step1Body="Откройте QuickJoin (/qj) и включите режим мониторинга в настройках. Выберите занятия, уточните поиск с помощью расширенных фильтров и нажмите «Поиск».",
        step2="2. ПРОДОЛЖАЙТЕ ИГРАТЬ",
        step2Body="QuickJoin отслеживает подходящие объявления и новые сообщения о поиске группы в чате LFG, пока вы играете. Щёлкните левой кнопкой, чтобы обновить объявления.",
        step3="3. ПРИСОЕДИНЯЙТЕСЬ К ГРУППЕ",
        step3Body="Нажмите «Шепнуть для вступления», «Пригласить» или «Подробнее».",
        controls="ЗНАЧОК: ЛКМ — повторить поиск  |  ПКМ — остановить отслеживание  |  ПЕРЕТАЩИТЬ — переместить",
        note="Объявления требуют ручного поиска; публичный чат LFG отслеживается автоматически.",
        never="Больше не показывать это сообщение",
        ok="Понятно!",
        help="Что нового / Справка",
        settings="Настройки:",
    },
    zhCN={
        title="FOREVER QUICKJOIN  |  更新内容",
        hero="边玩边寻找队伍",
        lead="减少等待时间，把更多时间留给任务、刷怪和探索。",
        step1="1. 开启监控模式",
        step1Body="打开 QuickJoin（/qj），然后在“设置”中开启监控模式。选择活动，使用“高级筛选”缩小搜索范围，再点击“搜索”。",
        step2="2. 继续游戏",
        step2Body="QuickJoin 会在游戏时监控匹配的队伍列表和公开组队聊天中的新招募消息。左键点击图标可重新搜索队伍列表。",
        step3="3. 加入队伍",
        step3Body="点击“密语申请加入”、“邀请”或“详情”。",
        controls="图标：左键重新搜索  |  右键停止监控  |  拖动可移动",
        note="队伍列表需手动搜索；监控期间会自动接收公开组队聊天消息。",
        never="不再显示此消息",
        ok="知道了",
        help="更新内容 / 帮助",
        settings="设置：",
    },
    zhTW={
        title="FOREVER QUICKJOIN  |  更新內容",
        hero="邊玩邊尋找隊伍",
        lead="減少等待時間，把更多時間留給任務、刷怪與探索。",
        step1="1. 開啟監控模式",
        step1Body="開啟 QuickJoin（/qj），接著在「設定」中開啟監控模式。選擇活動，使用「進階篩選」縮小搜尋範圍，再按下「搜尋」。",
        step2="2. 繼續遊戲",
        step2Body="QuickJoin 會在遊戲時監控符合條件的隊伍列表及公開組隊聊天的新招募訊息。左鍵點擊圖示可重新搜尋隊伍列表。",
        step3="3. 加入隊伍",
        step3Body="按下「密語申請加入」、「邀請」或「詳細資訊」。",
        controls="圖示：左鍵重新搜尋  |  右鍵停止監控  |  拖曳可移動",
        note="隊伍列表須手動搜尋；監控期間會自動接收公開組隊聊天訊息。",
        never="不再顯示此訊息",
        ok="知道了",
        help="更新內容 / 說明",
        settings="設定：",
    },
    koKR={
        title="FOREVER QUICKJOIN  |  새로운 기능",
        hero="게임하면서 파티 찾기",
        lead="대기 시간은 줄이고 퀘스트, 파밍, 탐험에 더 집중하세요.",
        step1="1. 모니터 모드 켜기",
        step1Body="QuickJoin(/qj)을 열고 설정에서 모니터 모드를 켜세요. 활동을 선택하고 고급 필터로 검색 조건을 조정한 다음 검색을 누르세요.",
        step2="2. 계속 플레이하기",
        step2Body="QuickJoin이 플레이 중 일치하는 파티 목록과 공개 파티 찾기 채팅의 새 모집 글을 감시합니다. 아이콘 좌클릭으로 파티 목록을 다시 검색할 수 있습니다.",
        step3="3. 파티 참여하기",
        step3Body="참여 귓속말, 초대 또는 상세 정보를 누르세요.",
        controls="아이콘: 좌클릭으로 다시 검색  |  우클릭으로 모니터 중지  |  드래그로 이동",
        note="파티 목록은 수동 검색이 필요하지만 공개 파티 채팅은 자동으로 수신합니다.",
        never="다시 표시하지 않기",
        ok="확인",
        help="새로운 기능 / 도움말",
        settings="설정:",
    },
}

-- All popup text follows the QuickJoin language selector; player-authored titles remain unchanged.
-- Source indicators are localized separately from Blizzard's group listing UI.
local chatUI={
    enUS={source="LFG CHAT",lfm="Group recruiting",lfg="Player looking for group",roles="Mentioned roles",unknown="Composition not verified",age="Chat post: %ds old",details="CHAT MESSAGE",members="Chat posts do not provide a verified roster",waiting="Watching LFG Chat and Group Listings",hint="LFG Chat live · Group Listings: click to search"},
    frFR={source="CHAT RDG",lfm="Groupe recrute",lfg="Joueur cherche un groupe",roles="Rôles mentionnés",unknown="Composition non vérifiée",age="Message : il y a %d s",details="MESSAGE DU CHAT",members="Le chat ne confirme pas les membres",waiting="Chat RdG et annonces surveillés",hint="Chat RdG en direct · Annonces : cliquer pour chercher"},
    deDE={source="LFG-CHAT",lfm="Gruppe sucht Mitglieder",lfg="Spieler sucht Gruppe",roles="Erwähnte Rollen",unknown="Besetzung nicht bestätigt",age="Chat-Nachricht: %ds alt",details="CHAT-NACHRICHT",members="Chatbeiträge enthalten keine bestätigte Gruppe",waiting="LFG-Chat und Gruppenangebote im Blick",hint="LFG-Chat live · Gruppenangebote per Klick suchen"},
    esES={source="CHAT DE GRUPOS",lfm="Grupo reclutando",lfg="Jugador busca grupo",roles="Roles mencionados",unknown="Composición sin verificar",age="Chat: hace %d s",details="MENSAJE DEL CHAT",members="El chat no confirma los miembros",waiting="Escuchando chat y anuncios",hint="Chat en vivo · Anuncios: buscar con un clic"},
    esMX={source="CHAT DE GRUPOS",lfm="Grupo reclutando",lfg="Jugador busca grupo",roles="Roles mencionados",unknown="Composición sin verificar",age="Chat: hace %d s",details="MENSAJE DEL CHAT",members="El chat no confirma los integrantes",waiting="Escuchando chat y anuncios",hint="Chat en vivo · Anuncios: buscar con un clic"},
    ptBR={source="CHAT DE GRUPOS",lfm="Grupo recrutando",lfg="Jogador procura grupo",roles="Funções mencionadas",unknown="Composição não verificada",age="Chat: há %d s",details="MENSAGEM DO CHAT",members="O chat não confirma integrantes",waiting="Monitorando chat e grupos",hint="Chat ao vivo · Grupos: clique para buscar"},
    ruRU={source="ЧАТ ПОИСКА",lfm="Группа набирает",lfg="Игрок ищет группу",roles="Упомянутые роли",unknown="Состав не подтверждён",age="Сообщение: %d с назад",details="СООБЩЕНИЕ",members="Состав группы в чате не подтверждён",waiting="Поиск в чате и списках",hint="Чат LFG в реальном времени · Объявления: поиск вручную"},
    zhCN={source="组队聊天",lfm="队伍招募",lfg="玩家寻队",roles="提及职责",unknown="队伍配置未核实",age="聊天：%d秒前",details="聊天消息",members="聊天消息无法验证队伍成员",waiting="监控聊天与队伍列表",hint="实时组队聊天 · 列表需点击搜索"},
    zhTW={source="組隊聊天",lfm="隊伍招募",lfg="玩家尋隊",roles="提及職責",unknown="隊伍配置未核實",age="聊天：%d秒前",details="聊天訊息",members="聊天訊息無法驗證隊伍成員",waiting="監控聊天與隊伍列表",hint="即時組隊聊天 · 列表需點擊搜尋"},
    koKR={source="파티 채팅",lfm="파티 모집 중",lfg="파티를 찾는 플레이어",roles="언급된 역할",unknown="파티 구성 확인 불가",age="채팅: %d초 전",details="채팅 메시지",members="채팅 글로는 파티 인원을 확인할 수 없습니다",waiting="파티 채팅 및 목록 감시 중",hint="실시간 파티 채팅 · 목록은 클릭하여 검색"},
}
local function ChatText(key)
    local row=chatUI[MonitorLanguage()] or chatUI.enUS
    return row[key] or chatUI.enUS[key]
end

local popupText={
    enUS={
        found="GROUP FOUND",
        monitor="QUICKJOIN MONITOR",
        noMatches="No matching groups yet",
        waitingGroup="Waiting for a matching Group Listing",
        stopped="Monitor is not searching",
        choose="Choose activities and click Search in /qj",
        members="members",
        browse="Use arrows to browse groups",
        listings="Group Listings only",
        waitingResults="Waiting for results",
        snapshot="Snapshot: %ds old",
        refresh="Search required to refresh",
        desc="DESCRIPTION",
        noDesc="No description",
        whisperJoin="Whisper to Join",
        invite="Invite",
        details="Details",
        less="Less",
        previous="Previous",
        next="Next",
        roster="GROUP MEMBERS (%d) · Right-click for /who or whisper",
        member="Member",
        leader="Leader",
        unknownRole="Unknown role",
        unknownClass="Class unknown",
        level="Lv",
        allMembers="All %d members shown",
        showMembers="Showing %d–%d of %d",
        rightWho="Right-click for /who or direct whisper",
        noTarget="Player name unavailable: individual actions disabled",
        prepWho="Prepare /who",
        memberWhisper="Whisper",
        close="Close",
        composition="Composition unavailable",
        tank="Tank",
        healer="Healer",
        toolMonitor="QuickJoin Monitor",
        toolActive="QuickJoin is monitoring Group Listings",
        toolIdle="QuickJoin is not searching",
        toolAge="Last manual search: %ds ago",
        toolPending="Waiting for the clicked search results...",
        toolNoPoll="New server searches require a player click.",
        toolLeft="Left-click: search again · Drag: move",
        toolRight="Right-click: stop monitoring",
        whispered="WHISPERED",
    },
    frFR={
        found="GROUPE TROUVÉ",
        monitor="MONITEUR QUICKJOIN",
        noMatches="Aucun groupe correspondant",
        waitingGroup="En attente d’une annonce correspondante",
        stopped="Surveillance arrêtée",
        choose="Choisissez des activités et cliquez sur Rechercher dans /qj",
        members="membres",
        browse="Utilisez les flèches pour parcourir les groupes",
        listings="Annonces de groupe uniquement",
        waitingResults="En attente des résultats",
        snapshot="Recherche : il y a %d s",
        refresh="Nouvelle recherche nécessaire",
        desc="DESCRIPTION",
        noDesc="Aucune description",
        whisperJoin="Chuchoter pour rejoindre",
        invite="Inviter",
        details="Détails",
        less="Réduire",
        previous="Préc.",
        next="Suiv.",
        roster="MEMBRES (%d) · Clic droit : /who ou chuchoter",
        member="Membre",
        leader="Chef",
        unknownRole="Rôle inconnu",
        unknownClass="Classe inconnue",
        level="Niv.",
        allMembers="%d membres affichés",
        showMembers="Affichage %d–%d sur %d",
        rightWho="Clic droit : /who ou chuchoter",
        noTarget="Nom indisponible : actions individuelles désactivées",
        prepWho="Préparer /who",
        memberWhisper="Chuchoter",
        close="Fermer",
        composition="Composition indisponible",
        tank="Tank",
        healer="Soigneur",
        toolMonitor="Moniteur QuickJoin",
        toolActive="QuickJoin surveille les annonces de groupe",
        toolIdle="Surveillance arrêtée",
        toolAge="Dernière recherche : il y a %d s",
        toolPending="En attente des résultats de la recherche...",
        toolNoPoll="Une nouvelle recherche nécessite un clic.",
        toolLeft="Clic gauche : relancer la recherche · Glisser : déplacer",
        toolRight="Clic droit : arrêter la surveillance",
        whispered="CHUCHOTÉ",
    },
    deDE={
        found="GRUPPE GEFUNDEN",
        monitor="QUICKJOIN-MONITOR",
        noMatches="Noch keine passenden Gruppen",
        waitingGroup="Warte auf passende Gruppenangebote",
        stopped="Monitor sucht nicht",
        choose="Aktivitäten auswählen und in /qj auf Suchen klicken",
        members="Mitglieder",
        browse="Mit den Pfeilen Gruppen durchblättern",
        listings="Nur Gruppenangebote",
        waitingResults="Warte auf Ergebnisse",
        snapshot="Suche vor %d s",
        refresh="Erneute Suche erforderlich",
        desc="BESCHREIBUNG",
        noDesc="Keine Beschreibung",
        whisperJoin="Beitritt flüstern",
        invite="Einladen",
        details="Details",
        less="Weniger",
        previous="Zurück",
        next="Weiter",
        roster="MITGLIEDER (%d) · Rechtsklick: /who oder flüstern",
        member="Mitglied",
        leader="Leiter",
        unknownRole="Rolle unbekannt",
        unknownClass="Klasse unbekannt",
        level="St.",
        allMembers="Alle %d Mitglieder angezeigt",
        showMembers="%d–%d von %d angezeigt",
        rightWho="Rechtsklick: /who oder flüstern",
        noTarget="Name nicht verfügbar: Einzelaktionen deaktiviert",
        prepWho="/who vorbereiten",
        memberWhisper="Flüstern",
        close="Schließen",
        composition="Zusammensetzung unbekannt",
        tank="Tank",
        healer="Heiler",
        toolMonitor="QuickJoin-Monitor",
        toolActive="QuickJoin überwacht Gruppenangebote",
        toolIdle="Monitor sucht nicht",
        toolAge="Letzte Suche vor %d s",
        toolPending="Warte auf die Suchergebnisse...",
        toolNoPoll="Neue Suchen erfordern einen Klick.",
        toolLeft="Linksklick: erneut suchen · Ziehen: verschieben",
        toolRight="Rechtsklick: Überwachung stoppen",
        whispered="ANGEFLÜSTERT",
    },
    esES={
        found="GRUPO ENCONTRADO",
        monitor="MONITOR QUICKJOIN",
        noMatches="Todavía no hay grupos compatibles",
        waitingGroup="Esperando un anuncio compatible",
        stopped="El monitor no está buscando",
        choose="Elige actividades y pulsa Buscar en /qj",
        members="miembros",
        browse="Usa las flechas para cambiar de grupo",
        listings="Solo anuncios de grupos",
        waitingResults="Esperando resultados",
        snapshot="Búsqueda de hace %d s",
        refresh="Es necesaria otra búsqueda",
        desc="DESCRIPCIÓN",
        noDesc="Sin descripción",
        whisperJoin="Susurrar para unirse",
        invite="Invitar",
        details="Detalles",
        less="Menos",
        previous="Anterior",
        next="Siguiente",
        roster="MIEMBROS (%d) · Clic derecho: /who o susurro",
        member="Miembro",
        leader="Líder",
        unknownRole="Rol desconocido",
        unknownClass="Clase desconocida",
        level="Nv.",
        allMembers="Se muestran los %d miembros",
        showMembers="Mostrando %d–%d de %d",
        rightWho="Clic derecho: /who o susurrar",
        noTarget="Nombre no disponible: acciones deshabilitadas",
        prepWho="Preparar /who",
        memberWhisper="Susurrar",
        close="Cerrar",
        composition="Composición no disponible",
        tank="Tanque",
        healer="Sanador",
        toolMonitor="Monitor QuickJoin",
        toolActive="QuickJoin vigila los anuncios de grupos",
        toolIdle="El monitor no está buscando",
        toolAge="Última búsqueda: hace %d s",
        toolPending="Esperando los resultados...",
        toolNoPoll="Para buscar otra vez debes hacer clic.",
        toolLeft="Clic izquierdo: volver a buscar · Arrastrar: mover",
        toolRight="Clic derecho: detener monitoreo",
        whispered="SUSURRADO",
    },
    esMX={
        found="GRUPO ENCONTRADO",
        monitor="MONITOR QUICKJOIN",
        noMatches="Aún no hay grupos compatibles",
        waitingGroup="Esperando un anuncio compatible",
        stopped="El monitor no está buscando",
        choose="Elige actividades y haz clic en Buscar en /qj",
        members="miembros",
        browse="Usa las flechas para cambiar de grupo",
        listings="Solo anuncios de grupos",
        waitingResults="Esperando resultados",
        snapshot="Búsqueda de hace %d s",
        refresh="Se necesita otra búsqueda",
        desc="DESCRIPCIÓN",
        noDesc="Sin descripción",
        whisperJoin="Susurrar para entrar",
        invite="Invitar",
        details="Detalles",
        less="Menos",
        previous="Anterior",
        next="Siguiente",
        roster="MIEMBROS (%d) · Clic derecho: /who o susurro",
        member="Miembro",
        leader="Líder",
        unknownRole="Rol desconocido",
        unknownClass="Clase desconocida",
        level="Nv.",
        allMembers="Se muestran los %d miembros",
        showMembers="Mostrando %d–%d de %d",
        rightWho="Clic derecho: /who o susurrar",
        noTarget="Nombre no disponible: acciones deshabilitadas",
        prepWho="Preparar /who",
        memberWhisper="Susurrar",
        close="Cerrar",
        composition="Composición no disponible",
        tank="Tanque",
        healer="Sanador",
        toolMonitor="Monitor QuickJoin",
        toolActive="QuickJoin vigila los anuncios de grupos",
        toolIdle="El monitor no está buscando",
        toolAge="Última búsqueda: hace %d s",
        toolPending="Esperando los resultados...",
        toolNoPoll="Para buscar otra vez debes hacer clic.",
        toolLeft="Clic izquierdo: volver a buscar · Arrastrar: mover",
        toolRight="Clic derecho: detener monitoreo",
        whispered="SUSURRADO",
    },
    ptBR={
        found="GRUPO ENCONTRADO",
        monitor="MONITOR QUICKJOIN",
        noMatches="Ainda não há grupos compatíveis",
        waitingGroup="Aguardando anúncio de grupo compatível",
        stopped="O monitor não está buscando",
        choose="Selecione atividades e clique em Buscar no /qj",
        members="membros",
        browse="Use as setas para ver outros grupos",
        listings="Apenas anúncios de grupos",
        waitingResults="Aguardando resultados",
        snapshot="Busca feita há %d s",
        refresh="É necessário buscar novamente",
        desc="DESCRIÇÃO",
        noDesc="Sem descrição",
        whisperJoin="Sussurrar para entrar",
        invite="Convidar",
        details="Detalhes",
        less="Menos",
        previous="Anterior",
        next="Próximo",
        roster="MEMBROS (%d) · Clique direito: /who ou sussurrar",
        member="Membro",
        leader="Líder",
        unknownRole="Função desconhecida",
        unknownClass="Classe desconhecida",
        level="Nv.",
        allMembers="Todos os %d membros exibidos",
        showMembers="Exibindo %d–%d de %d",
        rightWho="Clique direito: /who ou sussurrar",
        noTarget="Nome indisponível: ações desativadas",
        prepWho="Preparar /who",
        memberWhisper="Sussurrar",
        close="Fechar",
        composition="Composição indisponível",
        tank="Tanque",
        healer="Curador",
        toolMonitor="Monitor QuickJoin",
        toolActive="QuickJoin monitora anúncios de grupos",
        toolIdle="O monitor não está buscando",
        toolAge="Última busca há %d s",
        toolPending="Aguardando resultados da busca...",
        toolNoPoll="Uma nova busca requer um clique.",
        toolLeft="Clique esquerdo: pesquisar novamente · Arrastar: mover",
        toolRight="Clique direito: parar monitoramento",
        whispered="SUSSURRADO",
    },
    ruRU={
        found="ГРУППА НАЙДЕНА",
        monitor="МОНИТОР QUICKJOIN",
        noMatches="Подходящих групп пока нет",
        waitingGroup="Ожидание подходящего объявления",
        stopped="Поиск остановлен",
        choose="Выберите занятия и нажмите «Поиск» в /qj",
        members="участников",
        browse="Листайте группы стрелками",
        listings="Только объявления групп",
        waitingResults="Ожидание результатов",
        snapshot="Поиск %d с назад",
        refresh="Нужен новый поиск",
        desc="ОПИСАНИЕ",
        noDesc="Нет описания",
        whisperJoin="Шепнуть для входа",
        invite="Пригласить",
        details="Подробнее",
        less="Свернуть",
        previous="Назад",
        next="Далее",
        roster="УЧАСТНИКИ (%d) · ПКМ: /who или шепот",
        member="Участник",
        leader="Лидер",
        unknownRole="Роль неизвестна",
        unknownClass="Класс неизвестен",
        level="Ур.",
        allMembers="Показаны все %d участников",
        showMembers="Показаны %d–%d из %d",
        rightWho="ПКМ: /who или шепот",
        noTarget="Имя недоступно: действия отключены",
        prepWho="Подготовить /who",
        memberWhisper="Шепнуть",
        close="Закрыть",
        composition="Состав неизвестен",
        tank="Танк",
        healer="Лекарь",
        toolMonitor="Монитор QuickJoin",
        toolActive="QuickJoin отслеживает объявления групп",
        toolIdle="Поиск остановлен",
        toolAge="Последний поиск: %d с назад",
        toolPending="Ожидание результатов поиска...",
        toolNoPoll="Для нового поиска нужен щелчок.",
        toolLeft="ЛКМ: повторить поиск · Перетащить: переместить",
        toolRight="ПКМ: остановить поиск",
        whispered="НАПИСАЛИ",
    },
    zhCN={
        found="找到队伍",
        monitor="QUICKJOIN 监控",
        noMatches="暂时没有匹配的队伍",
        waitingGroup="正在等待匹配的队伍信息",
        stopped="监控已停止",
        choose="在 /qj 中选择活动并点击搜索",
        members="名成员",
        browse="使用箭头切换队伍",
        listings="仅监控组队列表",
        waitingResults="等待搜索结果",
        snapshot="搜索于 %d 秒前",
        refresh="需要重新搜索",
        desc="描述",
        noDesc="暂无描述",
        whisperJoin="密语申请加入",
        invite="邀请",
        details="详情",
        less="收起",
        previous="上一页",
        next="下一页",
        roster="队伍成员 (%d) · 右键查看 /who 或密语",
        member="成员",
        leader="队长",
        unknownRole="职责未知",
        unknownClass="职业未知",
        level="级",
        allMembers="已显示全部 %d 名成员",
        showMembers="显示第 %d–%d 名，共 %d 名",
        rightWho="右键查看 /who 或密语",
        noTarget="玩家姓名不可用：无法单独操作",
        prepWho="准备 /who",
        memberWhisper="密语",
        close="关闭",
        composition="队伍配置未知",
        tank="坦克",
        healer="治疗",
        toolMonitor="QuickJoin 监控",
        toolActive="QuickJoin 正在监控组队列表",
        toolIdle="监控已停止",
        toolAge="上次搜索：%d 秒前",
        toolPending="正在等待搜索结果...",
        toolNoPoll="新搜索需要玩家点击。",
        toolLeft="左键：重新搜索 · 拖动：移动",
        toolRight="右键：停止监控",
        whispered="已密语",
    },
    zhTW={
        found="找到隊伍",
        monitor="QUICKJOIN 監控",
        noMatches="目前沒有符合的隊伍",
        waitingGroup="正在等待符合條件的隊伍資訊",
        stopped="監控已停止",
        choose="在 /qj 中選擇活動並按下搜尋",
        members="名成員",
        browse="使用箭頭切換隊伍",
        listings="僅監控隊伍列表",
        waitingResults="等待搜尋結果",
        snapshot="搜尋於 %d 秒前",
        refresh="需要重新搜尋",
        desc="說明",
        noDesc="暫無說明",
        whisperJoin="密語申請加入",
        invite="邀請",
        details="詳細",
        less="收合",
        previous="上一頁",
        next="下一頁",
        roster="隊伍成員 (%d) · 右鍵查看 /who 或密語",
        member="成員",
        leader="隊長",
        unknownRole="職責未知",
        unknownClass="職業未知",
        level="級",
        allMembers="已顯示全部 %d 名成員",
        showMembers="顯示第 %d–%d 名，共 %d 名",
        rightWho="右鍵查看 /who 或密語",
        noTarget="玩家姓名不可用：無法單獨操作",
        prepWho="準備 /who",
        memberWhisper="密語",
        close="關閉",
        composition="隊伍配置未知",
        tank="坦克",
        healer="治療",
        toolMonitor="QuickJoin 監控",
        toolActive="QuickJoin 正在監控隊伍列表",
        toolIdle="監控已停止",
        toolAge="上次搜尋：%d 秒前",
        toolPending="正在等待搜尋結果...",
        toolNoPoll="新搜尋需要玩家點擊。",
        toolLeft="左鍵：重新搜尋 · 拖曳：移動",
        toolRight="右鍵：停止監控",
        whispered="已密語",
    },
    koKR={
        found="그룹 발견",
        monitor="QUICKJOIN 모니터",
        noMatches="아직 조건에 맞는 파티가 없습니다",
        waitingGroup="조건에 맞는 파티를 기다리는 중",
        stopped="모니터가 검색하지 않습니다",
        choose="/qj에서 활동을 선택하고 검색을 누르세요",
        members="명",
        browse="화살표로 다른 그룹 보기",
        listings="그룹 목록만 검색",
        waitingResults="검색 결과를 기다리는 중",
        snapshot="%d초 전 검색",
        refresh="새 검색이 필요합니다",
        desc="설명",
        noDesc="설명 없음",
        whisperJoin="참여 귓속말",
        invite="초대",
        details="상세",
        less="접기",
        previous="이전",
        next="다음",
        roster="파티원 (%d) · 우클릭: /who 또는 귓속말",
        member="파티원",
        leader="파티장",
        unknownRole="역할 미확인",
        unknownClass="직업 미확인",
        level="레벨",
        allMembers="총 %d명 표시",
        showMembers="%d–%d / %d명 표시",
        rightWho="우클릭: /who 또는 귓속말",
        noTarget="이름 확인 불가: 개인 작업 비활성화",
        prepWho="/who 준비",
        memberWhisper="귓속말",
        close="닫기",
        composition="파티 구성 정보 없음",
        tank="탱커",
        healer="힐러",
        toolMonitor="QuickJoin 모니터",
        toolActive="QuickJoin이 그룹 목록을 확인 중",
        toolIdle="모니터가 검색하지 않습니다",
        toolAge="마지막 검색: %d초 전",
        toolPending="검색 결과를 기다리는 중...",
        toolNoPoll="새 검색에는 직접 클릭이 필요합니다.",
        toolLeft="좌클릭: 다시 검색 · 드래그: 이동",
        toolRight="우클릭: 모니터 중지",
        whispered="귓속말 완료",
    },
}
MonitorLanguage = function()
    local locale=ForeverQuickJoinLocale
    if locale and type(locale.Current)=="function" then
        local _,effective=locale.Current()
        if type(effective)=="string" and introText[effective] then return effective end
    end
    local choice=ForeverQuickJoinDB and ForeverQuickJoinDB.languageChoice
    if choice=="auto" or not introText[choice] then
        choice=type(GetLocale)=="function" and GetLocale() or "enUS"
    end
    return introText[choice] and choice or "enUS"
end
local function MonitorCopy(key)
    local lang=introText[MonitorLanguage()] or introText.enUS
    return lang[key] or introText.enUS[key]
end
local function PopText(key)
    local lang=popupText[MonitorLanguage()] or popupText.enUS
    return lang[key] or popupText.enUS[key]
end
local function PopFmt(key,...)
    local fmt=PopText(key)
    return string.format(fmt,...)
end

RefreshIntroLocale = function()
    if intro and intro.labels then
        for key,label in pairs(intro.labels) do
            if label and type(label.SetText)=="function" then label:SetText(MonitorCopy(key)) end
        end
        if intro.okButton then
            intro.okButton:SetText(MonitorCopy("ok"))
            if intro.okButton.qjNative then intro.okButton.qjNative:SetText(MonitorCopy("ok")) end
        end
    end
    if M.RefreshPopup then M.RefreshPopup() end
    if ApplyTheme then ApplyTheme() end
end

local function IsCombat()
    return type(InCombatLockdown)=="function" and InCombatLockdown()==true
end
local function Label(parent,text,x,y,w,h,font)
    local l=parent:CreateFontString(nil,"OVERLAY",font or "GameFontHighlightSmall")
    l:SetPoint("TOPLEFT",parent,"TOPLEFT",x,-y)
    l:SetSize(w,h)
    l:SetJustifyH("LEFT")
    l:SetJustifyV("MIDDLE")
    l:SetWordWrap(true)
    l:SetText(text or "")
    return l
end
local function Button(parent,text,x,y,w,h,fn)
    local b=CreateFrame("Button",nil,parent,"BackdropTemplate")
    b:SetPoint("TOPLEFT",parent,"TOPLEFT",x,-y)
    b:SetSize(w,h)
    b:EnableMouse(true)
    b:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",
        edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1,
        insets={left=1,right=1,top=1,bottom=1}})
    local font=b:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    font:SetPoint("CENTER",b,"CENTER",0,0)
    font:SetWidth(math.max(15,w-12))
    font:SetJustifyH("CENTER")
    font:SetJustifyV("MIDDLE")
    b:SetFontString(font)
    b:SetText(text)
    b:SetScript("OnClick",fn)
    b:SetScript("OnEnter",function(self)
        self.qjHovered=true
        if ApplyButtonTheme then ApplyButtonTheme(self) end
    end)
    b:SetScript("OnLeave",function(self)
        self.qjHovered=false
        if ApplyButtonTheme then ApplyButtonTheme(self) end
    end)
    -- The Forever skin is the *real* built-in Blizzard button template, not
    -- a custom gold rectangle or an approximation of its normal/pushed art.
    -- It is a child of our wrapper: modern uses the wrapper, Forever uses
    -- this native child. Only one receives mouse input in each theme.
    local native=CreateFrame("Button",nil,b,"UIPanelButtonTemplate")
    native:SetAllPoints(b)
    native:SetText(text)
    native:SetScript("OnClick",fn)
    native:Hide()
    b.qjNative=native
    themedButtons[#themedButtons+1]=b
    return b
end
local function Backdrop(frame)
    frame:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",
        edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",
        tile=true,tileSize=16,edgeSize=16,
        insets={left=4,right=4,top=4,bottom=4}})
    frame:SetBackdropColor(.045,.065,.095,.98)
    frame:SetBackdropBorderColor(.57,.46,.24,.95)
end
-- Sound plays exactly once for each player-initiated Monitor Mode search,
-- whether launched through QuickJoin Search or a floating-icon left-click.
-- Match notifications and result updates are always silent.
local function Notify()
    if DB and DB.sound then PlayNotifySound(SOUND_ID,8458) end
end

-- FOREVER GROUP FINDER DATA --------------------------------------------------
local function ActivityInfo(id)
    if not (C_LFGList and type(C_LFGList.GetActivityInfoTable)=="function") then return nil end
    local ok,value=pcall(C_LFGList.GetActivityInfoTable,id)
    value=ok and Readable(value) or nil
    return type(value)=="table" and value or nil
end
local function IDs(info)
    local list,seenID={},{}
    if type(info)~="table" then return list end
    local values=Readable(info.activityIDs)
    if type(values)=="table" then
        for i=1,math.min(#values,30) do
            local id=Num(values[i])
            if id and id>0 and id==math.floor(id) and not seenID[id] then
                list[#list+1]=id;seenID[id]=true
            end
        end
    end
    if #list==0 then
        local id=Num(info.activityID)
        if id and id>0 and id==math.floor(id) then list[1]=id end
    end
    return list
end
local function ActivityName(id)
    local a=ActivityInfo(id)
    local name=a and (Str(a.fullName) or Str(a.name) or Str(a.shortName) or Str(a.zoneName))
    if name and ForeverQuickJoinLocale and type(ForeverQuickJoinLocale.TranslateDungeonName)=="function" then
        local ok,translated=pcall(ForeverQuickJoinLocale.TranslateDungeonName,name,Num(a.categoryID))
        if ok and Str(translated) then name=translated end
    end
    return name or ("Activity "..tostring(id))
end
local function ActivityList(info)
    local names={}
    for _,id in ipairs(IDs(info)) do names[#names+1]=ActivityName(id) end
    return #names>0 and table.concat(names," / ") or "Group Listing"
end
local function MaxPlayers(info)
    local capacity=nil
    for _,id in ipairs(IDs(info)) do
        local a=ActivityInfo(id)
        if a then
            local n=Num(a.maxNumPlayers)
            if (not n or n<2) and Num(a.categoryID)==2 then n=5 end
            if n and n>=2 then capacity=math.max(capacity or 0,n) end
        end
    end
    return capacity
end
local function Counts(id)
    if not (C_LFGList and type(C_LFGList.GetSearchResultMemberCounts)=="function") then return nil end
    local ok,c=pcall(C_LFGList.GetSearchResultMemberCounts,id)
    c=ok and Readable(c) or nil
    if type(c)~="table" then return nil end
    local result={}
    for _,r in ipairs({"TANK","HEALER","DAMAGER"}) do
        result[r]=Num(c[r])
        if not result[r] then return nil end
    end
    return result
end
local function NativeInfo(id)
    if not (C_LFGList and type(C_LFGList.GetSearchResultInfo)=="function") then return nil end
    local ok,v=pcall(C_LFGList.GetSearchResultInfo,id)
    v=ok and Readable(v) or nil
    return type(v)=="table" and v or nil
end
local function MemberInfo(id,index)
    local m={index=index}
    if C_LFGList and type(C_LFGList.GetSearchResultPlayerInfo)=="function" then
        local ok,p=pcall(C_LFGList.GetSearchResultPlayerInfo,id,index)
        p=ok and Readable(p) or nil
        if type(p)=="table" then
            m.name=SafeName(p.name)
            m.class=Str(p.classFilename)
            m.className=Str(p.className)
            m.level=Num(p.level)
            m.role=Str(p.assignedRole)
            m.spec=Str(p.specName)
            m.area=Str(p.areaName)
            m.leader=Readable(p.isLeader)==true
        end
    end
    if not m.class and C_LFGList and type(C_LFGList.GetSearchResultMemberInfo)=="function" then
        local ok,role,class,className,spec,leader=
            pcall(C_LFGList.GetSearchResultMemberInfo,id,index)
        if ok then
            m.role=Str(role);m.class=Str(class);m.className=Str(className)
            m.spec=Str(spec);m.leader=Readable(leader)==true
        end
    end
    if m.class then m.class=m.class:upper() end
    if not m.level or m.level<1 then m.level=nil end
    return m
end
local function Roster(id,info)
    local n=Num(info and info.numMembers) or 0
    local r={}
    for i=1,math.min(40,math.floor(n)) do
        local m=MemberInfo(id,i)
        if m.leader and not m.name then m.name=SafeName(info.leaderName) end
        r[#r+1]=m
    end
    return r
end
local TARGETS={
    [5]={TANK=1,HEALER=1,DAMAGER=3},
    [10]={TANK=2,HEALER=3,DAMAGER=5},
    [20]={TANK=3,HEALER=5,DAMAGER=12},
    [40]={TANK=4,HEALER=10,DAMAGER=26},
}
local function ScopeMatches(info)
    if not scope then return false end
    if scope.implicit then return true end -- returned by this completed manual search
    local ids=IDs(info)
    local chosen=scope.activityIDs or {}
    if #chosen>0 then
        local set={}
        for _,id in ipairs(chosen) do set[id]=true end
        for _,id in ipairs(ids) do if set[id] then return true end end
        return false
    end
    if scope.categoryID then
        for _,id in ipairs(ids) do
            local a=ActivityInfo(id)
            if a and Num(a.categoryID)==scope.categoryID then return true end
        end
    end
    return false
end
local function Matches(id,info)
    if not active or type(info)~="table" or not ScopeMatches(info) then return false end
    if Readable(info.isDelisted)~=false or Readable(info.hasSelf)~=false then return false end
    if not SafeName(info.leaderName) then return false end
    local n=Num(info.numMembers)
    if not n or n<1 or n>40 then return false end
    local cap=MaxPlayers(info)
    if not cap or n>=cap then return false end -- never claim unknown/full groups are available
    local a=scope.advanced or {}
    local f=scope.filters or {}
    local excludedStyles=a.excludedPlaystyles or {}
    local style=Num(info.generalPlaystyle)
    if style and excludedStyles[style] then return false end
    if Num(a.maxMembers) and a.maxMembers>0 and n>a.maxMembers then return false end
    if a.hasNotes and not Str(info.comment) then return false end
    if a.whisperable and (not SafeName(info.leaderName) or Readable(info.hasSelf)~=false) then return false end
    local excluded=a.excludedClasses or {}
    local needsClassCheck=false
    for _,v in pairs(excluded) do if v==true then needsClassCheck=true;break end end
    if needsClassCheck then
        for index=1,math.floor(n) do
            local m=MemberInfo(id,index)
            if not m.class or excluded[m.class] then return false end
        end
    end
    if a.ignoreTeamComposition then return true end
    local needs=f.needTank or f.needHealer or f.needDps
    if not needs and not f.hasTank and not f.hasHealer and not f.hasDps
        and not f.hasTankOrHealer then return true end
    local counts=Counts(id)
    if not counts then return false end
    if f.hasTank and counts.TANK<1 then return false end
    if f.hasHealer and counts.HEALER<1 then return false end
    if f.hasDps and counts.DAMAGER<1 then return false end
    if f.hasTankOrHealer and counts.TANK<1 and counts.HEALER<1 then return false end
    if needs then
        local t=TARGETS[cap]
        if not t then return false end
        if not ((f.needTank and counts.TANK<t.TANK)
            or (f.needHealer and counts.HEALER<t.HEALER)
            or (f.needDps and counts.DAMAGER<t.DAMAGER)) then return false end
    end
    return true
end

-- PLAYER-INITIATED MEMBER ACTIONS --------------------------------------------
local function OpenChat(text)
    if ChatFrameUtil and type(ChatFrameUtil.OpenChat)=="function" then
        ChatFrameUtil.OpenChat(text);return true
    elseif type(ChatFrame_OpenChat)=="function" then
        ChatFrame_OpenChat(text);return true
    end
    Print("Blizzard's chat input is unavailable.")
    return false
end
local function PrepareWho(name)
    if not SafeName(name) then return end
    if C_FriendList and type(C_FriendList.SetWhoToUi)=="function" then
        pcall(C_FriendList.SetWhoToUi,true)
    end
    local cmd='/who n-"'..name..'"'
    if OpenChat(cmd) then
        pendingWho={key=name:lower(),name=name,at=Now()}
        Print("Prepared /who for "..name..". Press Enter to look up location.")
    end
end
local function PrepareWhisper(name)
    if not SafeName(name) then return end
    -- Forever supports character names containing spaces. Native SendTell
    -- preserves the complete recipient; /cw is the correct client fallback.
    if ChatFrameUtil and type(ChatFrameUtil.SendTell)=="function" then
        ChatFrameUtil.SendTell(name)
    elseif type(ChatFrame_SendTell)=="function" then
        ChatFrame_SendTell(name)
    elseif not OpenChat("/cw "..name.." ") then
        return
    end
    Print("Prepared whisper for "..name..". Type message and press Enter.")
end
local function ReceiveWho()
    if not pendingWho or Now()-pendingWho.at>90 then pendingWho=nil;return end
    if not (C_FriendList and type(C_FriendList.GetNumWhoResults)=="function"
        and type(C_FriendList.GetWhoInfo)=="function") then return end
    local ok,total=pcall(C_FriendList.GetNumWhoResults)
    total=ok and Num(total) or nil
    if not total then return end
    local count,zone=0,nil
    for i=1,math.min(total,50) do
        local okay,p=pcall(C_FriendList.GetWhoInfo,i)
        p=okay and Readable(p) or nil
        if type(p)=="table" then
            local name=SafeName(p.fullName)
            local area=Str(p.area)
            if name and area and name:lower()==pendingWho.key then
                count=count+1;zone=area
            end
        end
    end
    if count==1 then
        whoZones[pendingWho.key]={area=zone,at=Now()}
        Print(pendingWho.name.." was last seen in "..zone.." (WHO snapshot).")
        pendingWho=nil
        if current then M.RefreshPopup() end
    end
end
local function WhoLocation(name)
    local rec=name and whoZones[name:lower()]
    if rec and Now()-rec.at<300 then return rec.area end
end
local function OpenContext(row)
    local name=row and SafeName(row.target)
    if not name or not context then
        Print("This member's name is unavailable; /who and whisper cannot be targeted.")
        return
    end
    selectedName=name
    context.title:SetText(Clean(name,35))
    context:ClearAllPoints()
    context:SetPoint("TOPRIGHT",row,"BOTTOMRIGHT",0,-2)
    context:Show()
end

-- NOTIFICATIONS -------------------------------------------------------------
-- The glowing orb represents a locally active Group Finder snapshot, NOT
-- an unrestricted server polling loop. Clicks are required for new searches.
UpdateIndicator = function()
    if not indicator then return end
    local enabled=DB and DB.enabledOnSearch==true
    -- Snapshot age is NOT a session stop condition. A timed search cannot
    -- legally re-query Blizzard, so the UI marks stale data and waits for
    -- a user click while keeping the monitoring controls alive.
    local listening=enabled and active==true
    indicator:SetShown(listening)
    if not listening then
        if popup then popup:Hide() end
        if context then context:Hide() end
    end
    indicator.active=listening
    if indicator.bg then
        indicator.bg:SetTexture(listening
            and "Interface\\AddOns\\ForeverQuickJoin\\Textures\\MonitorActive.tga"
            or  "Interface\\AddOns\\ForeverQuickJoin\\Textures\\MonitorInactive.tga")
    end
    if indicator.dots then
        for _,dot in ipairs(indicator.dots) do dot:SetShown(listening) end
    end

end
-- Both sources share a ranked queue; public LFG Chat posts have no verified
-- party composition and are deliberately never assigned an invented roster.
-- Group listings are filtered by Matches() before joining this queue.
-- A relevant support role takes precedence over party size, with stable
-- deterministic tie-breaking when compositions and party sizes are equal.
local function MonitorPlayerRole()
    local p=ForeverQuickJoinParty
    if p and type(p.RoleFor)=="function" then
        local role=Readable(p.RoleFor("player"))
        if role=="TANK" or role=="HEALER" or role=="DAMAGER" or role=="DPS" then
            return role
        end
    end
    if type(UnitGroupRolesAssigned)=="function" then
        local role=Readable(UnitGroupRolesAssigned("player"))
        if role=="TANK" or role=="HEALER" or role=="DAMAGER" then return role end
    end
    return "DAMAGER" -- known default; unassigned users see DPS-oriented ordering
end
local function RolePriority(m,playerRole)
    -- Recruitment text can suggest a vacancy but never proves a party roster.
    -- Put relevant LFM chat ads above unrelated/unverified posts, still behind
    -- verified Group Listings with actual complementary support-role counts.
    if m and m.chat then
        return m.chatKind=="LFM" and m.chatRequested
            and m.chatRequested[playerRole] and 0.5 or 0
    end
    local counts=m and m.roleCounts
    if not counts then return 0 end -- unknown composition is not presumed complete
    local hasTank=(Num(counts.TANK) or 0)>0
    local hasHealer=(Num(counts.HEALER) or 0)>0
    if playerRole=="TANK" then return hasHealer and 1 or 0 end
    if playerRole=="HEALER" then return hasTank and 1 or 0 end
    -- DPS players see groups with both support roles first, then either.
    return (hasTank and 1 or 0)+(hasHealer and 1 or 0)
end
local function SortPending()
    local role=MonitorPlayerRole()
    local selected=current
    table.sort(pending,function(a,b)
        local ac=whisperedLeaders[LeaderKey(a.leader)]~=nil
        local bc=whisperedLeaders[LeaderKey(b.leader)]~=nil
        if ac~=bc then return not ac end -- fresh groups above contacted ones
        local ar,br=RolePriority(a,role),RolePriority(b,role)
        if ar~=br then return ar>br end
        local am,bm=Num(a.members) or 0,Num(b.members) or 0
        if am~=bm then return am>bm end
        -- Preserve predictable ordering regardless of server result order.
        local an=(Str(a.title) or Str(a.activity) or ""):lower()
        local bn=(Str(b.title) or Str(b.activity) or ""):lower()
        if an~=bn then return an<bn end
        return tostring(a.key or a.id or "")<tostring(b.key or b.id or "")
    end)
    if selected then
        for i,m in ipairs(pending) do
            if m==selected then selectedIndex=i;return end
        end
    end
    selectedIndex=math.min(math.max(1,selectedIndex),math.max(1,#pending))
end
local function RememberWhisper(result)
    local leader=LeaderKey(result and result.leader)
    if leader then whisperedLeaders[leader]=Now() end
end
local function ShowNext()
    if not active or not popup then return end
    if #pending==0 then
        current=nil
        if popup:IsShown() then popup:Hide() end
        UpdateIndicator()
        return
    end
    if DB and DB.quietCombat and IsCombat() then
        popup:Hide();UpdateIndicator();return
    end
    selectedIndex=math.max(1,math.min(selectedIndex,#pending))
    current=pending[selectedIndex]
    if not current then return end
    if not popup:IsShown() then
        PositionPopup()
        popup:Show()
        PlayPopupIntro()
    end
    current.alerted=true
    M.RefreshPopup()
end
local function ToggleMatchesPopup()
    if not popup then return end
    if popup:IsShown() then
        popup:Hide()
        if context then context:Hide() end
        return
    end
    if not current and #pending>0 then
        selectedIndex=math.max(1,math.min(selectedIndex,#pending))
        current=pending[selectedIndex]
    end
    M.RefreshPopup()
    PositionPopup()
    popup:Show()
    PlayPopupIntro()
end
local function CycleGroup(direction)
    if #pending<2 then return end
    selectedIndex=((selectedIndex-1+direction)%#pending)+1
    current=pending[selectedIndex]
    expanded=false;rosterOffset=0
    if context then context:Hide() end
    M.RefreshPopup()
end
local function Next()
    -- X dismisses this listing, regardless of its contacted status.
    -- It never erases the session's Whispered marker for that leader.
    -- Only dismiss the displayed match. Seen identities prevent result-update
    -- events from bringing it back during the current search snapshot.
    if not current then
        if popup then popup:Hide() end
        return
    end
    -- Chat posts can be advertised again after ten minutes; Group Listings
    -- remain dismissed until the next player-initiated native search.
    dismissed[current.key]=current.chat and Now() or true
    if #pending>0 then table.remove(pending,selectedIndex) end
    current=nil;expanded=false;rosterOffset=0
    if context then context:Hide() end
    if #pending>0 then
        selectedIndex=selectedIndex>#pending and 1 or selectedIndex
        ShowNext() -- keep popup visible; update pager and show following match
    else
        selectedIndex=1
        if popup then popup:Hide() end
        UpdateIndicator() -- monitoring stays active, icon remains on screen
    end
end
Enqueue = function(result)
    if not active or not result then return end
    -- Keep contacted listings visible so their disabled Whispered button can
    -- be reviewed after Search Again. They must not re-trigger chat alerts.
    local contacted=whisperedLeaders[LeaderKey(result.leader)]~=nil
    local key=result.key
    if contacted and result.chat then
        -- Repeated chat ads from one contacted sender update the existing
        -- reviewable row instead of filling the queue with the same player.
        for _,existing in ipairs(pending) do
            if existing.chat and LeaderKey(existing.leader)==LeaderKey(result.leader) then
                seen[key]=Now()
                existing.chatAt=result.chatAt
                existing.chatChannel=result.chatChannel
                existing.chatKind=result.chatKind
                existing.chatRequested=result.chatRequested
                existing.chatRoles=result.chatRoles
                existing.title=result.title
                existing.activity=result.activity
                existing.comment=result.comment
                if popup and popup:IsShown() and current==existing then M.RefreshPopup() end
                return
            end
        end
    end
    local ignored=dismissed[key]
    if ignored then
        if result.chat and type(ignored)=="number" and Now()-ignored>=CHAT_TTL then
            dismissed[key]=nil
        else
            return
        end
    end
    local time=Now()
    if seen[key] and time-seen[key]<NOTIFY_DEDUP_SECONDS then return end
    seen[key]=time
    if #pending>=MAX_QUEUE then return end
    pending[#pending+1]=result
    if collectingResults then return end
    local showingContact=current and whisperedLeaders[LeaderKey(current.leader)]~=nil
    SortPending()
    UpdateIndicator()
    if not current and not contacted then
        ShowNext()
    elseif showingContact and not contacted then
        -- A genuinely new group must not remain hidden behind a contacted
        -- listing while the monitor is live.
        for i,m in ipairs(pending) do
            if m==result then selectedIndex=i;break end
        end
        ShowNext()
    elseif popup and popup:IsShown() then
        M.RefreshPopup()
    end
end
local function ActivateResult(id)
    local info=NativeInfo(id)
    if not Matches(id,info) then return end
    local leader=SafeName(info.leaderName)
    local ids=IDs(info)
    table.sort(ids)
    -- Result IDs can change across manual searches; dedupe by group identity.
    local key="finder:"..leader:lower()..":"..table.concat(ids,",")..":"..(Str(info.name) or ""):lower()
    local role=Counts(id)
    Enqueue({key=key,id=id,leader=leader,activity=ActivityList(info),activityIDs=IDs(info),
        title=Str(info.name),members=math.floor(Num(info.numMembers) or 0),
        cap=MaxPlayers(info),
        role=role and ("Tank "..role.TANK.."   Healer "..role.HEALER.."   DPS "..role.DAMAGER)
            or "Composition unavailable",roleCounts=role,
        comment=Str(info.comment),roster=Roster(id,info),verifiedAt=Now(),
        synthetic=false})
end
local function CaptureSearch()
    if not active or not scope then return end
    if not (C_LFGList and type(C_LFGList.GetFilteredSearchResults)=="function") then return end
    local ok,_,ids=pcall(C_LFGList.GetFilteredSearchResults)
    ids=ok and Readable(ids) or nil
    if type(ids)~="table" then
        Print("Group Finder results are inaccessible. Click Search again later.")
        return
    end
    verifiedAt=Now()
    searchIDs={}
    collectingResults=true
    for _,id in ipairs(ids) do
        id=Num(id)
        if id and id>0 then
            searchIDs[id]=verifiedAt
            ActivateResult(id)
        end
    end
    collectingResults=false
    SortPending()
    UpdateIndicator()
    if #pending>0 then ShowNext() end
end
local function UpdatedResult(id)
    id=Num(id)
    if not active or not id or not searchIDs[id]
        or not verifiedAt or Now()-verifiedAt>SEARCH_FRESH_SECONDS then return end
    local info=NativeInfo(id)
    if not Matches(id,info) then
        -- A listing can become full, be delisted, or stop satisfying filters.
        -- Remove it from the queue rather than showing a stale match.
        local removedCurrent=false
        local changed=false
        for i=#pending,1,-1 do
            if pending[i].id==id then
                changed=true
                if current==pending[i] then removedCurrent=true end
                table.remove(pending,i)
                if i<selectedIndex then selectedIndex=selectedIndex-1 end
            end
        end
        if changed then
            if context then context:Hide() end
            if removedCurrent then
                current=nil;expanded=false;rosterOffset=0
                if #pending>0 then
                    selectedIndex=math.min(math.max(1,selectedIndex),#pending)
                    ShowNext()
                elseif popup then popup:Hide() end
            else
                SortPending()
                if popup and popup:IsShown() then M.RefreshPopup() end
            end
        end
        return
    end
    for _,m in ipairs(pending) do
        if m.id==id then
            local counts=Counts(id)
            m.members=math.floor(Num(info.numMembers) or m.members)
            m.cap=MaxPlayers(info) or m.cap
            m.roleCounts=counts or m.roleCounts
            m.roster=Roster(id,info)
            m.comment=Str(info.comment)
            m.verifiedAt=Now()
            SortPending()
            if popup and popup:IsShown() then M.RefreshPopup() end
            return
        end
    end
    ActivateResult(id) -- newer matching result; dedupe by listing identity
end


-- LIVE PUBLIC LFG CHAT -----------------------------------------------------
-- We watch the same three public event families used by QuickJoin's LFG Chat.
-- This module never joins a channel, polls a server, or records posts in SV.
-- A post's roles, party size and membership are *not* verifiable Blizzard data.
local CHAT_INSTANCES={
    {"Scarlet Monastery",{"scarlet monastery","sm cath","sm gy","sm arm","sm lib","sm","cathedral"}},
    {"Shadowfang Keep",{"shadowfang keep","shadowfang","sfk"}},
    {"Deadmines",{"deadmines","vancleef","vc","dm westfall"}},
    {"Wailing Caverns",{"wailing caverns","wc"}},
    {"Ragefire Chasm",{"ragefire chasm","rfc"}},
    {"Blackfathom Deeps",{"blackfathom deeps","bfd"}},
    {"Stockades",{"stockades","stockade","stocks"}},
    {"Gnomeregan",{"gnomeregan","gnomer"}},
    {"Razorfen Kraul",{"razorfen kraul","rfk"}},
    {"Razorfen Downs",{"razorfen downs","rfd"}},
    {"Uldaman",{"uldaman","ulda"}},
    {"Zul'Farrak",{"zul farrak","zulfarrak","zf"}},
    {"Maraudon",{"maraudon","mara"}},
    {"Sunken Temple",{"sunken temple","temple of atal","atal hakkar"}},
    {"Blackrock Depths",{"blackrock depths","brd"}},
    {"Blackrock Spire",{"blackrock spire","lbrs","ubrs"}},
    {"Dire Maul",{"dire maul","dme","dmw","dmn","dm east","dm north"}},
    {"Stratholme",{"stratholme","strat"}},
    {"Scholomance",{"scholomance","scholo"}},
    {"Onyxia",{"onyxia","ony"}},
    {"Molten Core",{"molten core","mc"}},
    {"Zul'Gurub",{"zul gurub","zulgurub","zg"}},
    {"Blackwing Lair",{"blackwing lair","bwl"}},
    {"Ahn'Qiraj",{"ahn qiraj","aq20","aq40"}},
    {"Naxxramas",{"naxxramas","naxx"}},
    {"Hall of Thanes",{"hall of thanes"}},
    {"Ruins of Lordaeron",{"ruins of lordaeron"}},
    {"Excavation Site",{"excavation site"}},
    {"City of Dalaran",{"city of dalaran"}},
    {"The Drowned City",{"drowned city"}},
    {"Alcaz Prison",{"alcaz prison"}},
    {"Blackmaw Hold",{"blackmaw hold"}},
    {"Shaper's Terrace",{"shapers terrace","shaper's terrace"}},
    {"Hyjal Summit",{"hyjal summit"}},
    {"Barrow Deeps",{"barrow deeps"}},
    {"Krol'dok Stronghold",{"kroldok stronghold","krol'dok stronghold"}},
}
local CHAT_RAIDS={Onyxia=true,["Molten Core"]=true,["Zul'Gurub"]=true,
    ["Blackwing Lair"]=true,["Ahn'Qiraj"]=true,Naxxramas=true,["Hyjal Summit"]=true}
local function ChatDisplay(value)
    value=Str(value) or ""
    for _=1,3 do
        local reduced,n=value:gsub("||","|")
        value=reduced
        if n==0 then break end
    end
    value=value:gsub("|[Hh][^|]-|[hH](.-)|[hH]","%1")
    value=value:gsub("|[cC]%x%x%x%x%x%x%x%x","")
        :gsub("|[rR]",""):gsub("|[Tt][^|]-|[tT]","")
        :gsub("|[Hh][^|%s]*",""):gsub("|[hH]","")
        :gsub("[%c]"," ")
    return value
end
local function ChatNorm(s)
    s=ChatDisplay(s):lower():gsub("[%p]"," "):gsub("%s+"," ")
    return " "..s.." "
end
local function HasWord(s,w)
    local needle=ChatNorm(w)
    -- Trim normalization sentinels and require boundaries on both sides.
    return s:find(needle,1,true)~=nil
end
local function AnyWord(s,values)
    for _,word in ipairs(values) do if HasWord(s,word) then return true end end
    return false
end
local function ChatClassify(message)
    if not Str(message) or #message>1024 then return nil end
    local raw=ChatDisplay(message)
    local words=ChatNorm(raw)
    local hasQuestLink=message:find("|Hquest:",1,true)~=nil
        or message:find("||Hquest:",1,true)~=nil
    local lfm=AnyWord(words,{"lfm","lf1m","lf2m","lf3m","lf4m","lf5m",
        "looking for more","looking for members","need tank","need healer","need heal",
        "need heals","need dps","looking for tank","looking for healer",
        "looking for dps","group for","forming group","recrute","recrutamos",
        "buscamos","suche leute"})
        or words:find(" need%s+%d*%s*tank%s")~=nil
        or words:find(" need%s+%d*%s*heal%w*%s")~=nil
        or words:find(" need%s+%d*%s*dps%s")~=nil
    local lfg=AnyWord(words,{"lfg","looking for group","looking for a group",
        "anyone running","anyone doing","cherche groupe","busco grupo",
        "procuro grupo","suche gruppe"})
    if not lfm and not lfg then return nil end
    if AnyWord(words,{"wts","wtb","wtt","guild recruitment","selling", "buying",
        "boosting","boosts","portal","summons"}) and not (HasWord(words,"lfm") or HasWord(words,"lfg")) then
        return nil
    end
    if AnyWord(words,{"guild","guildmates","recruiting for guild"}) and
        not (HasWord(words,"lfm") or HasWord(words,"lfg")) then return nil end
    local activity,category="Unspecified","unspecified"
    for _,entry in ipairs(CHAT_INSTANCES) do
        if AnyWord(words,entry[2]) then
            activity=entry[1]
            category=CHAT_RAIDS[activity] and "raid" or "dungeon"
            break
        end
    end
    if category=="unspecified" and AnyWord(words,{"dungeon","dungeons","instance","instances"}) then
        activity="Any dungeon";category="dungeon"
    elseif category=="unspecified" and AnyWord(words,{"raid","raids"}) then
        activity="Any raid";category="raid"
    end
    if category=="unspecified" and (hasQuestLink
        or AnyWord(words,{"quest","quests","questing","escort","elite","group quest","zone","grinding"})) then
        activity="Quests / Zones";category="quest"
    end
    return {kind=lfm and "LFM" or "LFG",activity=activity,category=category,
        words=words,display=raw,original=message}
end
local function ChatRequestedRole(words,role)
    local terms=role=="TANK" and {"tank","tanks"}
        or role=="HEALER" and {"healer","healers","heal","heals"}
        or {"dps","damage"}
    for _,term in ipairs(terms) do
        if words:find(" need%s+%d*%s*"..term.."%s")
            or words:find(" lf%s+%d*%s*"..term.."%s")
            or words:find(" looking for%s+%d*%s*"..term.."%s")
            or words:find(" lf%d+m%s+"..term.."%s")
            or words:find(" %d+%s+"..term.."%s") then return true end
    end
    return false
end
local function ChatSelectedActivity(entry)
    if not scope then return nil end
    local ids=scope.activityIDs or {}
    if #ids==0 then
        -- Keep category selection even without explicit activity IDs.
        local id=Num(scope.categoryID)
        if id and id>0 then
            if id==2 and entry.category~="dungeon" then return nil end
            if id==3 and entry.category~="raid" then return nil end
            if id==4 and entry.category~="quest" then return nil end
        end
        return entry.category~="unspecified" and entry.activity or nil
    end
    for _,id in ipairs(ids) do
        local a=ActivityInfo(id)
        if a then
            local name=Str(a.fullName) or Str(a.name) or Str(a.shortName) or Str(a.zoneName)
            local category=Num(a.categoryID)
            if name then
                local names={name}
                if Str(a.shortName) then names[#names+1]=a.shortName end
                if Str(a.zoneName) then names[#names+1]=a.zoneName end
                local lower=name:lower()
                for _,known in ipairs(CHAT_INSTANCES) do
                    if lower:find(known[1]:lower(),1,true) then
                        -- Sub-zones of Scarlet Monastery must not all match "SM".
                        local qualifier=lower:find("cathedral",1,true) and {"sm cath","cathedral"}
                            or lower:find("graveyard",1,true) and {"sm gy","graveyard"}
                            or lower:find("armory",1,true) and {"sm arm","armory"}
                            or lower:find("library",1,true) and {"sm lib","library"}
                        for _,alias in ipairs(qualifier or known[2]) do names[#names+1]=alias end
                    end
                end
                -- For an unqualified activity, prefer recognized canonical name.
                if entry.category=="quest" and (category==4 or lower:find("quest",1,true)
                    or lower:find("zone",1,true)) then return entry.activity end
                for _,candidate in ipairs(names) do
                    if HasWord(entry.words,candidate) then return name end
                end
            end
        end
    end
    return nil -- cannot prove advertised activity belongs to selection
end
local function ChatPasses(entry)
    if not active or not scope or not entry or not SafeName(entry.sender) then return nil end
    if type(UnitName)=="function" then
        local selfName=SafeName(UnitName("player"))
        if selfName and entry.sender:lower()==selfName:lower() then return nil end
    end
    -- Public LFG posts do not carry a verified roster, vacancy count,
    -- classes, playstyle, or group size. The structured Group Listings
    -- must still respect ALL advanced composition and exclusion filters.
    -- Chat notifications intentionally use only selected category/activities.
    return ChatSelectedActivity(entry)
end
local function ReceiveChat(event,message,sender,_,channelName,_,_,_,_,baseName)
    -- This event handler does not modify QuickJoin's own public-chat inbox.
    -- All state stays in-memory, and only monitor-active messages are eligible.
    if not active or not (DB and DB.enabledOnSearch) then return end
    message=Str(message)
    sender=SafeName(sender)
    if not message or not sender then return end
    local entry=ChatClassify(message)
    if not entry then return end
    entry.sender=sender
    local activity=ChatPasses(entry)
    if not activity then return end
    local channel=event=="CHAT_MSG_SAY" and "Say"
        or event=="CHAT_MSG_YELL" and "Yell"
        or Str(baseName) or Str(channelName) or "Public"
    channel=channel:gsub("^%d+%.%s*",""):sub(1,40)
    local key="chat:"..sender:lower()..":"..entry.original:lower():gsub("%s+"," ")
    local roleHints,requested={},{}
    for _,name in ipairs({"TANK","HEALER","DAMAGER"}) do
        if ChatRequestedRole(entry.words,name) then
            requested[name]=true
            roleHints[#roleHints+1]=name=="DAMAGER" and "DPS" or name
        end
    end
    chatObserved=chatObserved+1
    local before=seen[key]
    Enqueue({key=key,id=nil,chat=true,chatKind=entry.kind,
        chatChannel=channel,chatAt=Now(),leader=sender,activity=activity,
        title=activity,comment=entry.original,chatRoles=table.concat(roleHints,", "),
        chatRequested=requested,members=nil,cap=nil,roleCounts=nil,roster={},synthetic=false})
    if not before and seen[key] then
        chatMatched=chatMatched+1
        -- One gentle notification at most every 15 seconds despite chat spam.
        if not whisperedLeaders[LeaderKey(sender)] and DB.sound
            and not (DB.quietCombat and IsCombat())
            and Now()-chatAlertAt>=15 then
            chatAlertAt=Now()
            PlayNotifySound(47615,47615)
        end
    end
end
local function PruneExpiredChat()
    if not active or #pending==0 then return end
    local removed=false
    for i=#pending,1,-1 do
        local m=pending[i]
        local mismatch=false
        if m.chat and m.comment and Now()-m.chatAt<CHAT_TTL then
            local classification=ChatClassify(m.comment)
            if classification then
                classification.sender=m.leader
                mismatch=not ChatPasses(classification)
            else
                mismatch=true
            end
        end
        if m.chat and (not m.chatAt or Now()-m.chatAt>=CHAT_TTL or mismatch) then
            if m==current then current=nil end
            if i<selectedIndex then selectedIndex=selectedIndex-1 end
            table.remove(pending,i)
            removed=true
        end
    end
    if removed then
        selectedIndex=math.min(math.max(1,selectedIndex),math.max(1,#pending))
        if not current and #pending>0 then ShowNext()
        elseif #pending==0 and popup then popup:Hide()
        elseif popup and popup:IsShown() then M.RefreshPopup() end
    end
end

local function RefreshCachedResults()
    -- This is a READ-ONLY check of Blizzard's EXISTING client cache. It must
    -- NEVER invoke C_LFGList.Search, simulate an input, or claim the server
    -- was queried. Only the player's click makes a fresh server search.
    if not active or awaitingResults or not verifiedAt
        or Now()-verifiedAt>=SEARCH_FRESH_SECONDS then return end
    if not (C_LFGList and type(C_LFGList.GetFilteredSearchResults)=="function") then return end
    local ok,_,ids=pcall(C_LFGList.GetFilteredSearchResults)
    ids=ok and Readable(ids) or nil
    if type(ids)~="table" then return end
    local changed=0
    for _,value in ipairs(ids) do
        local id=Num(value)
        if id and id>0 then
            -- New IDs are only accepted from the same still-fresh client-side
            -- snapshot; matching listings are checked against saved filters.
            if searchIDs[id] then
                UpdatedResult(id)
            elseif changed<MAX_QUEUE then
                searchIDs[id]=verifiedAt
                ActivateResult(id)
                changed=changed+1
            end
        end
    end
end

-- PRIMARY ACTIONS ------------------------------------------------------------
local function RoleLabel()
    local value=ForeverQuickJoinParty and ForeverQuickJoinParty.RoleFor
        and Readable(ForeverQuickJoinParty.RoleFor("player")) or nil
    if value=="TANK" then return "Tank" end
    if value=="HEALER" then return "Healer" end
    if value=="DAMAGER" then return "DPS" end
    return "DPS"
end
local function WhisperMessage(m)
    local db=type(ForeverQuickJoinDB)=="table" and ForeverQuickJoinDB or {}
    local template=Str(db.template)
        or "Level {level} {class} {role} LFG {activity}, Current location: {location}, inv please!"
    local class=type(UnitClass)=="function" and Str(UnitClass("player")) or "player"
    local level=type(UnitLevel)=="function" and Num(UnitLevel("player")) or nil
    local zone=type(GetRealZoneText)=="function" and Str(GetRealZoneText()) or nil
    local party=type(GetNumGroupMembers)=="function" and Num(GetNumGroupMembers()) or nil
    local fields={level=tostring(level or "?"),class=class or "player",role=RoleLabel(),
        activity=m.activity or "group",location=zone or "Unknown",party="Party of "..tostring(math.max(1,party or 0)),
        partycount=tostring(math.max(1,party or 0)),name=type(UnitName)=="function" and Str(UnitName("player")) or "player"}
    local function Expand()
        return (template:gsub("{([%w_]+)}",function(k) return fields[k:lower()] or "{"..k.."}" end))
    end
    local text=Expand()
    if #text>255 then fields.activity=(m.activity or "group"):sub(1,35);text=Expand() end
    return text
end
local function Fresh(m)
    if not active or not m or m.synthetic or not m.id or not verifiedAt
        or Now()-verifiedAt>SEARCH_FRESH_SECONDS or not searchIDs[m.id] then
        Print("This Group Finder snapshot is old. Refresh with QuickJoin's Search button.")
        return nil
    end
    local info=NativeInfo(m.id)
    if not info or Readable(info.isDelisted)~=false or Readable(info.hasSelf)~=false
        or SafeName(info.leaderName)~=m.leader then
        Print("This listing could not be verified. Search again before contacting it.")
        return nil
    end
    return info
end
local function Whisper()
    local m=current
    if not m or whisperedLeaders[LeaderKey(m.leader)]
        or (not m.chat and not Fresh(m)) then return end
    if m.chat and (not active or not m.chatAt or Now()-m.chatAt>=CHAT_TTL
        or not SafeName(m.leader)) then return end
    if C_ChatInfo and type(C_ChatInfo.InChatMessagingLockdown)=="function"
        and C_ChatInfo.InChatMessagingLockdown() then
        Print("Chat messaging is locked; whisper not sent.");return
    end
    local template=(type(ForeverQuickJoinDB)=="table" and Str(ForeverQuickJoinDB.template)) or ""
    local groupSize=type(GetNumGroupMembers)=="function" and Num(GetNumGroupMembers()) or 0
    if groupSize>0 and (template:find("{party}",1,true) or template:find("{role}",1,true))
        and ForeverQuickJoinParty and type(ForeverQuickJoinParty.NeedsReview)=="function" then
        local ok,n=pcall(ForeverQuickJoinParty.NeedsReview)
        if ok and Num(n) and n>0 then
            Print("Confirm uncertain party roles before whispering.")
            if type(ForeverQuickJoinParty.Open)=="function" then ForeverQuickJoinParty.Open() end
            return
        end
    end
    local message
    if m.chat and m.chatKind=="LFG" then
        local L=ForeverQuickJoinLocale
        if L and type(L.ChatLFGReply)=="function" then
            local ok,v=pcall(L.ChatLFGReply,m.activity)
            if ok then message=Str(v) end
        end
        message=message or ("I saw your LFG post for "..m.activity
            ..". Are you still looking for a group?")
    else
        message=WhisperMessage(m)
    end
    if message=="" or #message>255 then
        Print("Whisper template is empty or exceeds the 255-byte limit.");return
    end
    if attempts[m.leader] and Now()-attempts[m.leader]<3 then
        Print("You already contacted this leader recently.");return
    end
    local sender=C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
    if type(sender)~="function" then Print("Whisper API is unavailable.");return end
    -- Protected messaging only in this direct button OnClick path.
    sender(message,"WHISPER",nil,m.leader)
    attempts[m.leader]=Now()
    if not m.chat and ForeverQuickJoinApplications
        and type(ForeverQuickJoinApplications.TrackSent)=="function" then
        m.applicationRecord=m.applicationRecord or {leader=m.leader,at=Now()}
        pcall(ForeverQuickJoinApplications.TrackSent,m.applicationRecord,NativeInfo(m.id) or {},message)
    end
    RememberWhisper(m) -- only after the player explicitly sends a whisper
    Print("Whisper submitted to "..m.leader.." (delivery not confirmed). Marked Whispered for this session.")
    -- Keep the listing on screen: disable/grey its existing Whisper button.
    -- This also updates any other queued adverts from the same leader.
    SortPending()
    for i,listing in ipairs(pending) do
        if listing==m then selectedIndex=i;break end
    end
    if popup and popup:IsShown() then M.RefreshPopup() end
end
local function Invite()
    local m=current
    if not m then return end
    local info
    if m.chat then
        -- LFG poster is a player seeking a group, not a verified listing leader.
        if not active or m.chatKind~="LFG" or not m.chatAt
            or Now()-m.chatAt>=CHAT_TTL then return end
        if type(InCombatLockdown)=="function" and InCombatLockdown() then
            Print("Leave combat before inviting.");return
        end
    else
        info=Fresh(m)
        if not info then return end
        if Num(info.numMembers)~=1 then
            Print("Invite is available only for a solo listed group leader.");return
        end
    end
    if type(IsInGroup)=="function" and IsInGroup() then
        local leader=(type(UnitIsGroupLeader)=="function" and UnitIsGroupLeader("player"))
            or (type(IsPartyLeader)=="function" and IsPartyLeader())
        if not leader then Print("Only the party leader can invite.");return end
    end
    local invite=C_PartyInfo and C_PartyInfo.InviteUnit or InviteUnit
    if type(invite)~="function" then Print("Invite API unavailable.");return end
    invite(m.leader) -- physical click only; no auto invitations
    Print("Invitation requested for "..m.leader.." (acceptance not confirmed).")
    Next()
end

-- UI -------------------------------------------------------------------------
local iconCoordinates={
    WARRIOR={0,.25,0,.25},MAGE={.25,.5,0,.25},ROGUE={.5,.75,0,.25},DRUID={.75,1,0,.25},
    HUNTER={0,.25,.25,.5},SHAMAN={.25,.5,.25,.5},PRIEST={.5,.75,.25,.5},WARLOCK={.75,1,.25,.5},
    PALADIN={0,.25,.5,.75},
}
local function SetIcon(tile,token)
    local region=tile.icon
    local coords=(type(CLASS_ICON_TCOORDS)=="table" and CLASS_ICON_TCOORDS[token or ""]) or iconCoordinates[token or ""]
    if coords then
        region:SetTexture("Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES")
        region:SetTexCoord(coords[1],coords[2],coords[3],coords[4])
        region:Show()
    else
        region:Hide()
    end
end
local function RenderRoster()
    if not rosterTitle then return end
    local list=current and current.roster or {}
    local n=#list
    local maxOffset=math.max(0,n-ROW_COUNT)
    rosterOffset=math.max(0,math.min(rosterOffset,maxOffset))
    rosterTitle:SetText(PopFmt("roster",n))
    for i=1,ROW_COUNT do
        local tile=rosterRows[i]
        local m=list[i+rosterOffset]
        tile.member=m
        if m then
            tile:Show()
            tile.target=(not current.synthetic) and SafeName(m.name) or nil
            tile.name:SetText(Clean(m.name or (PopText("member").." "..m.index),36)
                ..(m.leader and (" |cffffd166("..PopText("leader")..")|r") or ""))
            local role=m.role=="DAMAGER" and "DPS" or (m.role=="TANK" and PopText("tank"))
                or (m.role=="HEALER" and PopText("healer")) or (m.role or PopText("unknownRole"))
            local zone=WhoLocation(m.name) or m.area
            local className=m.className or m.class or PopText("unknownClass")
            if ForeverQuickJoinLocale and type(ForeverQuickJoinLocale.Translate)=="function" then
                className=ForeverQuickJoinLocale.Translate(className) or className
            end
            local line=(PopText("level").." "..tostring(m.level or "?")).."  ·  "
                ..Clean(className,22).."  ·  "..Clean(role,25)
            if zone then line=line.."  ·  "..Clean(zone,38) end
            tile.details:SetText(line)
            SetIcon(tile,m.class)
            -- Palette is applied after roster rendering; do not hard-code the theme.
            tile.hovered=false
        else
            tile:Hide();tile.target=nil
        end
    end
    rosterPager:SetText(n>ROW_COUNT
        and PopFmt("showMembers",rosterOffset+1,math.min(rosterOffset+ROW_COUNT,n),n)
        or PopFmt("allMembers",n))
    prevButton:SetEnabled(rosterOffset>0)
    nextButton:SetEnabled(rosterOffset+ROW_COUNT<n)
end
-- Palette changes are applied immediately, not after /reload.
local function CurrentPalette()
    local style=(ForeverQuickJoinDB and ForeverQuickJoinDB.theme=="Modern") and "Modern" or "Forever"
    local transparent=ForeverQuickJoinDB and ForeverQuickJoinDB.themeTransparency==true or false
    if ForeverQuickJoinTheme and type(ForeverQuickJoinTheme.Current)=="function" then
        local ok,a,b=pcall(ForeverQuickJoinTheme.Current)
        if ok then style=a or "Forever";transparent=b==true end
    end
    if style=="Modern" then
        return {mode="Modern",bg={.067,.081,.106,transparent and .68 or .98},border={.24,.38,.53,1},
            card={.10,.14,.19,.98},hover={.20,.30,.40,.99},
            accent={.66,.83,1},muted={.73,.80,.88},
            button={.115,.175,.245,1},buttonHover={.17,.27,.37,1},
            primary={.115,.33,.49,1},primaryHover={.17,.43,.59,1},
            buttonBorder={.30,.50,.67,1},buttonText={.88,.94,1}}
    end
    return {mode="Forever",bg={.078,.064,.047,transparent and .68 or .98},border={.68,.52,.26,1},
        card={.13,.11,.079,.98},hover={.29,.22,.10,.99},
        accent={1,.82,.39},muted={.84,.76,.61},
        button={.25,.17,.085,1},buttonHover={.37,.27,.12,1},
        primary={.30,.225,.080,1},primaryHover={.45,.33,.12,1},
        buttonBorder={.78,.60,.29,1},buttonText={1,.87,.54}}
end
-- Restyle both the panel chrome and the actual clickable buttons, not a tint
-- over Blizzard's unchanged UIPanelButtonTemplate texture.
ApplyPanelTheme = function(frame,c)
    if not frame then return end
    if c.mode=="Modern" then
        frame:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",
            edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=2,
            insets={left=2,right=2,top=2,bottom=2}})
    else
        frame:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",
            edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=16,
            insets={left=4,right=4,top=4,bottom=4}})
    end
    frame:SetBackdropColor(unpack(c.bg))
    frame:SetBackdropBorderColor(unpack(c.border))
end
ApplyButtonTheme = function(b, palette)
    if not b then return end
    local c=palette or CurrentPalette()
    local modern=c.mode=="Modern"
    local native=b.qjNative
    if native then
        native:SetText(b:GetText() or "")
        native:SetEnabled(b:IsEnabled())
        if modern then native:Hide() else native:Show() end
    end
    local font=b:GetFontString()
    if not modern then
        -- Actual UIPanelButtonTemplate has its own typography and all normal,
        -- pressed, disabled and highlight textures, just like the main addon.
        b:EnableMouse(false)
        b:SetBackdrop(nil)
        if font then font:Hide() end
        return
    end
    b:EnableMouse(true)
    b:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",
        edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1,
        insets={left=1,right=1,top=1,bottom=1}})
    local enabled=b:IsEnabled()
    local primary=b.qjPrimary==true
    local paint=primary and (b.qjHovered and c.primaryHover or c.primary)
        or (b.qjHovered and c.buttonHover or c.button)
    b:SetBackdropColor(paint[1],paint[2],paint[3],enabled and paint[4] or .47)
    b:SetBackdropBorderColor(c.buttonBorder[1],c.buttonBorder[2],c.buttonBorder[3],enabled and 1 or .35)
    if font then
        font:Show()
        local rgb=c.buttonText
        font:SetTextColor(rgb[1],rgb[2],rgb[3],enabled and 1 or .44)
    end
end
ApplyTheme = function()
    local c=CurrentPalette()
    for _,f in ipairs({popup,context,intro}) do
        if f then ApplyPanelTheme(f,c) end
    end
    for _,f in ipairs({header,rosterTitle,intro and intro.title,intro and intro.hero}) do
        if f and type(f.SetTextColor)=="function" then f:SetTextColor(unpack(c.accent)) end
    end
    for _,f in ipairs({queueText,freshnessText,subtext,rosterPager,intro and intro.note}) do
        if f and type(f.SetTextColor)=="function" then f:SetTextColor(unpack(c.muted)) end
    end
    for _,b in ipairs(themedButtons) do ApplyButtonTheme(b,c) end
    for _,row in ipairs(rosterRows) do
        if row and row.SetBackdropColor then
            local shade=row.hovered and c.hover or c.card
            row:SetBackdropColor(unpack(shade))
        end
    end
end
M.ApplyTheme=ApplyTheme

function M.RefreshPopup()
    if not popup then return end
    local m=current
    local age=verifiedAt and math.floor(Now()-verifiedAt) or nil
    if m then
        header:SetText(m.chat and ChatText("source") or PopText("found"))
        local activity=m.activityIDs and #m.activityIDs>0
            and ActivityList({activityIDs=m.activityIDs}) or m.activity
        activityText:SetText(Clean(m.title or activity,90))
        if m.chat then
            subtext:SetText((m.chatKind=="LFM" and ChatText("lfm") or ChatText("lfg"))
                .." · "..Clean(m.chatChannel,55))
            roleText:SetText(Clean(m.leader,70).." · "
                ..(m.chatRoles~="" and (ChatText("roles")..": "..Clean(m.chatRoles,55))
                    or ChatText("unknown")))
        else
            subtext:SetText(Clean(activity,90))
            local counts=m.roleCounts
            local composition=counts and (PopText("tank").." "..counts.TANK.."  "
                ..PopText("healer").." "..counts.HEALER.."  DPS "..counts.DAMAGER)
                or (m.role=="Composition unavailable" and PopText("composition") or m.role)
            roleText:SetText(tostring(m.members).."/"..tostring(m.cap or "?").." "
                ..PopText("members").."  ·  "..Clean(composition,70))
        end
    else
        header:SetText(PopText("monitor"))
        activityText:SetText(PopText("noMatches"))
        subtext:SetText(active and ChatText("waiting") or PopText("stopped"))
        roleText:SetText(PopText("choose"))
    end
    queueText:SetText(#pending>1 and PopText("browse") or (m and m.chat and ChatText("source") or PopText("listings")))
    freshnessText:SetText((m and m.chat and (ChatText("age")):format(math.max(0,math.floor(Now()-m.chatAt))))
        or (active and awaitingResults) and PopText("waitingResults") or
        (active and age and age<SEARCH_FRESH_SECONDS and PopFmt("snapshot",age)) or
        (active and ChatText("hint")) or PopText("refresh"))
    local rawDescription=m and m.comment or PopText("noDesc")
    if m and m.chat then rawDescription=ChatDisplay(rawDescription) end
    descriptionText:SetText((m and m.chat and ChatText("details") or PopText("desc"))
        .."\n"..Clean(rawDescription,m and m.chat and 450 or 280))
    local chatFresh=m and m.chat and m.chatAt and Now()-m.chatAt<CHAT_TTL
    local listingFresh=m and not m.chat and m.id and verifiedAt
        and Now()-verifiedAt<SEARCH_FRESH_SECONDS and searchIDs[m.id]
    local alreadyWhispered=m and whisperedLeaders[LeaderKey(m.leader)]~=nil
    whisperButton:SetEnabled(m~=nil and not alreadyWhispered
        and not m.synthetic and active and not not (chatFresh or listingFresh))
    inviteButton:SetEnabled(m~=nil and not m.synthetic and active and
        (not not (chatFresh and m.chatKind=="LFG" or (listingFresh and m.members==1))))
    expandButton:SetEnabled(m~=nil)
    local queueCount=#pending
    if prevGroupButton then prevGroupButton:SetShown(m~=nil and queueCount>1) end
    if nextGroupButton then nextGroupButton:SetShown(m~=nil and queueCount>1) end
    if groupPager then
        if m then
            groupPager:SetText(tostring(math.max(1,selectedIndex)).."/"..tostring(math.max(1,queueCount)))
            groupPager:SetShown(true)
        else
            groupPager:SetText("")
            groupPager:SetShown(false)
        end
    end
    whisperButton:SetText(alreadyWhispered and PopText("whispered") or PopText("whisperJoin"))
    inviteButton:SetText(PopText("invite"))
    expandButton:SetText(expanded and PopText("less") or PopText("details"))
    prevButton:SetText(PopText("previous"))
    nextButton:SetText(PopText("next"))
    if contextWho then contextWho:SetText(PopText("prepWho")) end
    if contextWhisper then contextWhisper:SetText(PopText("memberWhisper")) end
    if contextCloseButton then contextCloseButton:SetText(PopText("close")) end
    local details=expanded and m~=nil
    popup:SetHeight(details and (m.chat and 367 or 497) or 159)
    if details and m.chat then descriptionText:SetHeight(180) else descriptionText:SetHeight(59) end
    descriptionText:SetShown(details)
    rosterTitle:SetShown(details and not m.chat)
    prevButton:SetShown(details and not m.chat)
    nextButton:SetShown(details and not m.chat)
    rosterPager:SetShown(details and not m.chat)
    for _,row in ipairs(rosterRows) do row:SetShown(details and not m.chat) end
    if details and not m.chat then RenderRoster() end
    if PositionPopup then PositionPopup() end
    ApplyTheme()
end
local function MakePopup()
    if popup then return end
    popup=CreateFrame("Frame","ForeverQuickJoinMonitorPopup",UIParent,"BackdropTemplate")
    popup:SetSize(342,159)
    popup:SetFrameStrata("DIALOG");popup:SetFrameLevel(150)
    popup:SetClampedToScreen(true);popup:EnableMouse(true)
    popup:SetPoint("TOPLEFT",UIParent,"CENTER",0,0)
    Backdrop(popup)
    header=Label(popup,"GROUP FOUND",12,10,190,19,"GameFontNormalSmall")
    prevGroupButton=Button(popup,"<",210,8,23,22,function() CycleGroup(-1) end)
    groupPager=Label(popup,"1/1",236,10,43,18,"GameFontHighlightSmall")
    nextGroupButton=Button(popup,">",279,8,23,22,function() CycleGroup(1) end)
    Button(popup,"X",309,7,23,22,function() Next() end)
    activityText=Label(popup,"",12,33,318,24,"GameFontHighlight")
    subtext=Label(popup,"",12,57,319,18,"GameFontHighlightSmall")
    roleText=Label(popup,"",12,77,318,19,"GameFontHighlightSmall")
    whisperButton=Button(popup,"Whisper to Join",12,103,135,26,Whisper)
    whisperButton.qjPrimary=true
    inviteButton=Button(popup,"Invite",154,103,72,26,Invite)
    expandButton=Button(popup,"Details",233,103,97,26,function()
        if not current then return end
        expanded=not expanded;rosterOffset=0
        if context then context:Hide() end
        M.RefreshPopup()
    end)
    queueText=Label(popup,"",140,134,1,18,"GameFontDisableSmall")
    queueText:Hide() -- top pager already handles group browsing
    freshnessText=Label(popup,"",12,134,318,18,"GameFontDisableSmall")
    descriptionText=Label(popup,"",12,165,318,59,"GameFontHighlightSmall")
    rosterTitle=Label(popup,"",12,233,318,21,"GameFontNormalSmall")
    for i=1,ROW_COUNT do
        local tile=CreateFrame("Button",nil,popup,"BackdropTemplate")
        tile:SetPoint("TOPLEFT",popup,"TOPLEFT",12,-(260+(i-1)*29))
        tile:SetSize(318,28);tile:SetFrameLevel(popup:GetFrameLevel()+3)
        tile:EnableMouse(true)
        tile:RegisterForClicks("LeftButtonUp","RightButtonUp")
        tile:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"})
        tile:SetBackdropColor(.13,.11,.079,.98)
        tile.icon=tile:CreateTexture(nil,"ARTWORK")
        tile.icon:SetPoint("LEFT",tile,"LEFT",5,0);tile.icon:SetSize(21,21)
        tile.name=Label(tile,"",32,0,280,15,"GameFontHighlightSmall")
        tile.details=Label(tile,"",32,14,280,13,"GameFontDisableSmall")
        tile:SetScript("OnEnter",function(self)
            self.hovered=true
            local c=CurrentPalette();self:SetBackdropColor(unpack(c.hover))
            if GameTooltip then
                GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
                local member=self.member
                GameTooltip:AddLine(member and (member.name or (PopText("member").." "..member.index)) or PopText("member"),1,.83,.2)
                if member and member.spec then GameTooltip:AddLine(member.spec,.85,.85,.9) end
                GameTooltip:AddLine(self.target and PopText("rightWho")
                    or PopText("noTarget"),.72,.85,1,true)
                GameTooltip:Show()
            end
        end)
        tile:SetScript("OnLeave",function(self)
            self.hovered=false
            local c=CurrentPalette();self:SetBackdropColor(unpack(c.card))
            if GameTooltip then GameTooltip:Hide() end
        end)
        tile:SetScript("OnClick",function(self,button)
            if button=="RightButton" then OpenContext(self)
            elseif button=="LeftButton" and context then context:Hide() end
        end)
        rosterRows[#rosterRows+1]=tile
    end
    prevButton=Button(popup,"Previous",12,466,79,23,function()
        rosterOffset=math.max(0,rosterOffset-ROW_COUNT);RenderRoster()
    end)
    nextButton=Button(popup,"Next",251,466,79,23,function()
        rosterOffset=rosterOffset+ROW_COUNT;RenderRoster()
    end)
    rosterPager=Label(popup,"",98,468,149,19,"GameFontDisableSmall")
    popup:SetScript("OnMouseWheel",function(_,delta)
        if expanded then
            rosterOffset=rosterOffset-(delta>0 and 1 or -1)
            RenderRoster()
        end
    end)
    popup:EnableMouseWheel(true)
    -- Clicking empty background should never accidentally expand/close details.
    context=CreateFrame("Frame","ForeverQuickJoinMonitorMemberMenu",UIParent,"BackdropTemplate")
    context:SetSize(225,86);context:SetFrameStrata("TOOLTIP");context:SetFrameLevel(200)
    context:SetClampedToScreen(true);context:EnableMouse(true)
    Backdrop(context)
    context.title=Label(context,"",9,3,208,18,"GameFontNormalSmall")
    contextWho=Button(context,"Prepare /who",8,24,103,26,function()
        local name=selectedName;context:Hide();PrepareWho(name)
    end)
    contextWhisper=Button(context,"Whisper",118,24,99,26,function()
        local name=selectedName;context:Hide();PrepareWhisper(name)
    end)
    contextCloseButton=Button(context,"Close",72,56,81,22,function() context:Hide() end)
    context:Hide();popup:Hide()
    ApplyTheme()
end
-- Choose one of the orb's two sides, and open upward if the player
-- dragged the orb near the lower edge of the screen. The popup stays linked.
PositionPopup = function()
    if not popup or not indicator or not indicator.GetLeft then return end
    local parent=UIParent
    local left=Num(indicator:GetLeft())
    local right=Num(indicator:GetRight())
    local top=Num(indicator:GetTop())
    local bottom=Num(indicator:GetBottom())
    local w=Num(parent:GetWidth()) or 1920
    local h=Num(parent:GetHeight()) or 1080
    local width=Num(popup:GetWidth()) or 342
    local height=Num(popup:GetHeight()) or 159
    local spaceRight=right and (w-right) or w/2
    local spaceLeft=left or w/2
    local spaceDown=bottom or h/2
    local spaceUp=top and (h-top) or h/2
    local openRight=(spaceRight>=width+12) or spaceRight>=spaceLeft
    local openDown=(spaceDown>=height+12) or spaceDown>=spaceUp
    popup:ClearAllPoints()
    if openRight and openDown then
        popup:SetPoint("TOPLEFT",indicator,"TOPRIGHT",8,4)
    elseif openRight then
        popup:SetPoint("BOTTOMLEFT",indicator,"BOTTOMRIGHT",8,-4)
    elseif openDown then
        popup:SetPoint("TOPRIGHT",indicator,"TOPLEFT",-8,4)
    else
        popup:SetPoint("BOTTOMRIGHT",indicator,"BOTTOMLEFT",-8,-4)
    end
end
PlayPopupIntro = function()
    if not popup then return end
    -- A quick scale/fade makes the card appear to grow out of the status orb.
    popup:SetScale(.82)
    popup:SetAlpha(.06)
    popup.openAmount=0
    popup:SetScript("OnUpdate",function(self,elapsed)
        self.openAmount=math.min(1,(self.openAmount or 0)+(elapsed or 0)/.23)
        local t=self.openAmount
        local eased=1-(1-t)*(1-t)*(1-t)
        self:SetScale(.82+.18*eased)
        self:SetAlpha(.06+.94*eased)
        if t>=1 then self:SetScript("OnUpdate",nil) end
    end)
end
local function MoveOrbToSavedPosition()
    if not indicator or not DB then return end
    indicator:ClearAllPoints()
    indicator:SetPoint("CENTER",UIParent,"CENTER",DB.orbX or 310,DB.orbY or -90)
end
local function MakeIndicator()
    if indicator then return end
    indicator=CreateFrame("Button","ForeverQuickJoinMonitorIndicator",UIParent)
    -- Smaller, unobtrusive crest: 40px hitbox with 44px artwork.
    indicator:SetSize(40,40)
    indicator:SetFrameStrata("HIGH");indicator:SetFrameLevel(110)
    indicator:SetClampedToScreen(true)
    indicator:SetMovable(true)
    indicator:EnableMouse(true)
    indicator:RegisterForClicks("LeftButtonUp","RightButtonUp")
    indicator:RegisterForDrag("LeftButton")
    indicator.bg=indicator:CreateTexture(nil,"ARTWORK")
    indicator.bg:SetSize(44,44)
    indicator.bg:SetPoint("CENTER",indicator,"CENTER",0,0)
    indicator.bg:SetTexture("Interface\\AddOns\\ForeverQuickJoin\\Textures\\MonitorInactive.tga")
    indicator.dots={}
    for i=1,6 do
        local dot=indicator:CreateTexture(nil,"OVERLAY")
        dot:SetTexture("Interface\\AddOns\\ForeverQuickJoin\\Textures\\OrbGlow.tga")
        dot:SetSize(5.5,5.5)
        indicator.dots[#indicator.dots+1]=dot
    end
    indicator.time=0
    indicator:SetScript("OnUpdate",function(self,elapsed)
        -- UI animation is local only; NEVER calls Blizzard's Search API.
        if self.active then
            self.time=(self.time+(elapsed or 0)*2.6)%(math.pi*2)
            for i,dot in ipairs(self.dots) do
                local angle=self.time+(i-1)*math.pi/3
                dot:ClearAllPoints()
                dot:SetPoint("CENTER",self,"CENTER",math.cos(angle)*19,math.sin(angle)*19)
                dot:SetVertexColor(.2,.92,.42,1)
                dot:SetAlpha(.10+.55*(i/6)^2)
            end
        end
    end)
    indicator:SetScript("OnDragStart",function(self)
        self:StartMoving()
    end)
    indicator:SetScript("OnDragStop",function(self)
        self:StopMovingOrSizing()
        if DB and self.GetCenter and UIParent.GetCenter then
            local x,y=self:GetCenter()
            local cx,cy=UIParent:GetCenter()
            if x and y and cx and cy then
                DB.orbX=math.floor(x-cx+.5)
                DB.orbY=math.floor(y-cy+.5)
            end
        end
        if popup and popup:IsShown() then PositionPopup() end
    end)
    indicator:SetScript("OnClick",function(self,button)
        if button=="RightButton" then
            if active then M.Stop(true) end -- stop sound; icon disappears
            return
        end
        if button~="LeftButton" or not active or not (DB and DB.enabledOnSearch) then return end
        -- Left-click always requests another player-initiated search.
        local previous=scope
        local cat=previous and Num(previous.categoryID)
        local activities=previous and previous.activityIDs
        if not cat or type(activities)~="table" or #activities==0 then
            Print("No saved Group Finder search. Open /qj, choose an activity, and click Search first.")
            if mainWindow then mainWindow:Show() end
            return
        end
        if not (C_LFGList and type(C_LFGList.Search)=="function") then
            Print("Group Finder search is unavailable on this client.")
            return
        end
        -- One actual left-click = one native Group Finder search request.
        -- A ticker, callback, or simulated click NEVER invokes Search().
        -- Snapshot the current advanced filters to respect recent user changes.
        local settings=ForeverQuickJoinDB or {}
        local newScope={categoryID=cat,activityIDs=Copy(activities,2),
            filters=Copy(settings.filters or previous.filters or {},4),
            advanced=Copy(settings.advanced or previous.advanced or {},4)}
        Start(newScope,false)
        orbSearchAttempt=true;orbSearchAt=Now()
        local ok=C_LFGList.Search(cat,0,0,nil,false,nil,activities)
        orbSearchAttempt=false
        if ok==false then
            awaitingResults=false
            UpdateIndicator()
            Print("WoW declined the search. Monitoring continues; try Search in /qj.")
        else
            Notify() -- one sound per successful player-initiated refresh
        end
    end)
    indicator:SetScript("OnEnter",function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self,"ANCHOR_LEFT")
        GameTooltip:AddLine(PopText("toolMonitor"),1,.82,.3)
        if active then
            GameTooltip:AddLine(ChatText("waiting"),.35,1,.46)
            if verifiedAt then
                GameTooltip:AddLine(PopFmt("toolAge",math.floor(Now()-verifiedAt)),1,1,1)
            else
                GameTooltip:AddLine(PopText("toolPending"),1,1,1)
            end
        else
            GameTooltip:AddLine(PopText("toolIdle"),.80,.84,.88)
        end
        GameTooltip:AddLine(ChatText("hint"),.95,.79,.40,true)
        GameTooltip:AddLine(PopText("toolLeft"),.8,.9,1)
        GameTooltip:AddLine(PopText("toolRight"),.8,.9,1)
        GameTooltip:Show()
    end)
    indicator:SetScript("OnLeave",function() if GameTooltip then GameTooltip:Hide() end end)
    MoveOrbToSavedPosition()
    UpdateIndicator()
end

function M.Stop(userClicked)
    local shouldSound=active and userClicked==true
    active=false;awaitingResults=false;searchIDs={};collectingResults=false
    wasGrouped=false;dismissed={}
    -- Contacted-leader markers survive stop/start; reset only on reload/logout.
    verifiedAt=nil
    if popup then popup:Hide() end
    if context then context:Hide() end
    UpdateIndicator()
    if shouldSound then PlayNotifySound(STOP_SOUND_ID,17341) end
    Print("Monitor stopped. The icon is hidden until you click Search in QuickJoin again.")
end
Start = function(manualScope,playSound)
    SetDB()
    local capture=manualScope or (latestSearch and Now()-latestSearch.at<=2 and latestSearch or nil)
    -- If restricted call parameters cannot be observed, use only the freshly
    -- completed result set from the click; never invent selected activity IDs.
    scope={categoryID=capture and capture.categoryID or nil,
        activityIDs=capture and Copy(capture.activityIDs,2) or {},
        filters=manualScope and Copy(manualScope.filters,4)
            or Copy((ForeverQuickJoinDB or {}).filters or {},4),
        advanced=manualScope and Copy(manualScope.advanced,4)
            or Copy((ForeverQuickJoinDB or {}).advanced or {},4),
        implicit=not capture}
    local restarting=active
    local keepChat,keepDismissed,keepSeen={},{},{}
    if restarting then
        for _,m in ipairs(pending) do
            if m.chat and m.chatAt and Now()-m.chatAt<CHAT_TTL then
                keepChat[#keepChat+1]=m
                keepSeen[m.key]=seen[m.key]
            end
        end
        for key,v in pairs(dismissed) do
            if type(key)=="string" and key:sub(1,5)=="chat:"
                and type(v)=="number" and Now()-v<CHAT_TTL then
                keepDismissed[key]=v
            end
        end
    end
    dismissed=keepDismissed;seen=keepSeen -- refresh finder only; retain live chat
    if popup then popup:Hide() end
    if context then context:Hide() end
    wasGrouped=InGroup()
    active=true;awaitingResults=true;current=nil;pending=keepChat;searchIDs={};collectingResults=false
    if not restarting then
        lfgJoinAttempts=0
        lfgJoinLastAt=-100000
        lfgJoinNotBefore=Now()+8
    end
    -- Search Again preserves the in-memory Whispered markers.
    expanded=false;rosterOffset=0;selectedIndex=1;verifiedAt=nil;lastUserSearchAt=Now()
    MakePopup();MakeIndicator();UpdateIndicator()
    if #pending>0 then SortPending();ShowNext() end
    if playSound then Notify() end -- QuickJoin Search click.
    if mainWindow then mainWindow:Hide() end
    Print("Monitor started: LFG Chat live; Group Listings update on each manual Search.")
    if C_Timer and type(C_Timer.After)=="function" then
        -- Avoid competing with the core Chat module's on-login join attempt.
        C_Timer.After(8,function()
            if active and DB and DB.enabledOnSearch then TryAutoJoinLFG(false) end
        end)
    else
        TryAutoJoinLFG(false)
    end
    if C_Timer and type(C_Timer.After)=="function" then
        local startAt=lastUserSearchAt
        C_Timer.After(16,function()
            if active and awaitingResults and lastUserSearchAt==startAt then
                awaitingResults=false
                UpdateIndicator()
                if popup and popup:IsShown() then M.RefreshPopup() end
                Print("Search timed out. Monitor remains active; click Search to request new listings.")
            end
        end)
    end
end
local function SetMonitorEnabled(enabled)
    SetDB()
    DB.enabledOnSearch=enabled==true
    if not DB.enabledOnSearch then
        M.Stop()
        pending={};current=nil;seen={};selectedIndex=1
        if popup then popup:Hide() end
    end
    MakeIndicator()
    UpdateIndicator()
end
M.SetEnabled=SetMonitorEnabled

-- Forever QuickJoin 0.9.8's Theme / Language menu uses an unnamed
-- DropdownButton. Reinstall its public menu description, retaining EVERY
-- original option and adding Monitor Mode next to Transparency. No core files
-- are changed by this local companion build.
local function AttachThemeMenu(win)
    if themeDropdown or not win or type(win.GetChildren)~="function" then return end
    local selected
    for _,child in ipairs({win:GetChildren()}) do
        if child and type(child.GetObjectType)=="function"
            and (child:GetObjectType()=="DropdownButton" or child:GetObjectType()=="Button")
            and type(child.SetupMenu)=="function" then
            local point,relative,relativePoint,x,y=child:GetPoint(1)
            local width=type(child.GetWidth)=="function" and child:GetWidth() or nil
            if point=="TOPLEFT" and (relative==win or not relative)
                and (type(x)=="number" and math.abs(x-322)<=4)
                and (type(y)=="number" and math.abs(y+12)<=4)
                and (not width or math.abs(width-121)<8) then
                selected=child;break
            end
        end
    end
    if not selected then return end
    themeDropdown=selected
    RenameSettingsLabel(win)
    selected:SetupMenu(function(_,menu)
        local Theme=ForeverQuickJoinTheme
        local locale=ForeverQuickJoinLocale
        local function T(value)
            return locale and locale.Translate and locale.Translate(value) or value
        end
        local lang=locale and locale.Current and locale.Current() or "auto"
        local titles={frFR="Mode surveillance",deDE="Überwachungsmodus",esES="Modo monitor",
            esMX="Modo monitor",ptBR="Modo de monitoramento",ruRU="Режим поиска",
            zhCN="监控模式",zhTW="監控模式",koKR="모니터 모드"}
        local modeLabel=titles[lang] or "Monitor Mode"
        local joinLabels={
            enUS="Auto-join LookingForGroup",
            frFR="Rejoindre automatiquement LookingForGroup",
            deDE="LookingForGroup automatisch beitreten",
            esES="Unirse automáticamente a LookingForGroup",
            esMX="Unirse automáticamente a LookingForGroup",
            ptBR="Entrar automaticamente em LookingForGroup",
            ruRU="Автовход в LookingForGroup",
            zhCN="自动加入 LookingForGroup 频道",
            zhTW="自動加入 LookingForGroup 頻道",
            koKR="LookingForGroup 채널 자동 참가",
        }
        local actualLang=type(MonitorLanguage)=="function" and MonitorLanguage() or lang
        local autoJoinLabel=joinLabels[actualLang] or joinLabels.enUS
        local function Radio(label,checked,click)
            local option=menu:CreateRadio(label,checked,click)
            if option and type(option.SetSelectionIgnored)=="function" then option:SetSelectionIgnored() end
            return option
        end
        local function Checkbox(label,checked,click)
            local option=menu:CreateCheckbox(label,checked,click)
            if option and type(option.SetSelectionIgnored)=="function" then option:SetSelectionIgnored() end
            return option
        end
        if type(menu.SetTag)=="function" then
            menu:SetTag("MENU_FOREVER_QUICKJOIN_SETTINGS")
        end
        local name,transparent=Theme.Current()
        menu:CreateTitle(T("Theme"))
        Radio("Forever",function() return name=="Forever" end,function() Theme.Select("Forever") end)
        Radio("Modern",function() return name=="Modern" end,function() Theme.Select("Modern") end)
        Checkbox(T("Transparency"),function() return transparent end,
            function() Theme.ToggleTransparency() end)
        menu:CreateDivider()
        Checkbox(modeLabel,function() return DB and DB.enabledOnSearch==true end,
            function() SetMonitorEnabled(not (DB and DB.enabledOnSearch==true)) end)
        Checkbox(autoJoinLabel,ChatAutoJoinOn,function()
            if type(ForeverQuickJoinDB)~="table" then ForeverQuickJoinDB={} end
            local enabled=not ChatAutoJoinOn()
            ForeverQuickJoinDB.chatAutoJoin=enabled
            if enabled then
                lfgJoinAttempts=0
                lfgJoinLastAt=-100000
                TryAutoJoinLFG(true) -- a direct user click; includes when monitor is off
            else
                lfgJoinStatus="disabled in QuickJoin"
            end
        end)
        menu:CreateButton(MonitorCopy("help"),function() if ShowIntro then ShowIntro(true) end end)
        menu:CreateDivider()
        menu:CreateTitle(T("Language"))
        Checkbox(T("Translate Dungeon Names"),
            function() return locale and locale.DungeonNamesEnabled and locale.DungeonNamesEnabled() end,
            function()
                if locale and locale.SetTranslateDungeonNames then
                    locale.SetTranslateDungeonNames(not locale.DungeonNamesEnabled())
                    if win.QuickJoinLanguageChanged then win:QuickJoinLanguageChanged() end
                end
            end)
        local choices={
            {"auto",T("Automatic (client language)")},
            {"enUS","English"},{"frFR","Français"},{"deDE","Deutsch"},
            {"esES","Español"},{"esMX","Español (Latinoamérica)"},
            {"ptBR","Português (Brasil)"},{"ruRU","Русский"},
            {"zhCN","简体中文"},{"zhTW","繁體中文"},{"koKR","한국어"},
        }
        for _,option in ipairs(choices) do
            local code,label=option[1],option[2]
            Radio(label,function() return locale and locale.Current and locale.Current()==code end,
                function()
                    if locale and locale.Select then
                        locale.Select(code)
                        Theme.ApplyNew()
                        if win.QuickJoinLanguageChanged then win:QuickJoinLanguageChanged() end
                        if RefreshIntroLocale then RefreshIntroLocale() end
                        if RenameSettingsLabel then RenameSettingsLabel(win) end
                    end
                end)
        end
    end)
end


-- Main QuickJoin reassigns the listing Invite state to English on every
-- RefreshListingButtons pass (e.g. "In grp"), while Locale.Refresh changes it
-- back. Hook only those addon-owned buttons, translating synchronously, so
-- there is no alternating English/localized frame and no core-file changes.
local hookedInviteButtons=setmetatable({}, {__mode="k"})
local function InstallInviteTranslationHooks()
    local root=_G.ForeverQuickJoinFindContent
    if not root or type(hooksecurefunc)~="function" then return end
    local visited,n={},0
    local function Visit(frame)
        if not frame or visited[frame] or n>=900 then return end
        visited[frame]=true;n=n+1
        local btn=frame.qjChatInvite
        if btn and not hookedInviteButtons[btn] then
            local ok=pcall(hooksecurefunc,btn,"SetText",function(self,value)
                if self.qjLocalizing==true or type(value)~="string" then return end
                if value~="In grp" and value~="Invite" and value~="Sent"
                    and value~="Joined" and value~="Failed" then return end
                -- Never substitute an unavailable-invite label: stay on Invite.
                local source=value=="In grp" and "Invite" or value
                local L=ForeverQuickJoinLocale
                local translated=L and type(L.Translate)=="function" and L.Translate(source) or source
                if type(translated)=="string" and translated~=value then
                    self.qjLocalizing=true
                    self:SetText(translated)
                    self.qjLocalizing=false
                end
            end)
            if ok then hookedInviteButtons[btn]=true end
        end
        if type(frame.GetChildren)=="function" then
            for _,child in ipairs({frame:GetChildren()}) do Visit(child) end
        end
    end
    Visit(root)
end

local function Attach(win)
    if not win then return end
    if attached then
        AttachThemeMenu(win);RenameSettingsLabel(win);InstallInviteTranslationHooks()
        return
    end
    local finder=_G.ForeverQuickJoinFindContent
    if not finder or type(finder.GetChildren)~="function" then return end
    local match
    for _,child in ipairs({finder:GetChildren()}) do
        if child and type(child.GetObjectType)=="function" and child:GetObjectType()=="Button"
            and type(child.GetText)=="function" and type(child.GetScript)=="function"
            and child:GetScript("OnClick") then
            local caption=Str(child:GetText())
            local source=ForeverQuickJoinLocale and ForeverQuickJoinLocale.SourceFor
                and ForeverQuickJoinLocale.SourceFor(child)
            if caption=="Search" or source=="Search" then match=child;break end
        end
    end
    if not match then return end
    searchButton=match;mainWindow=win;attached=true
    InstallInviteTranslationHooks()
    if type(win.HookScript)=="function" then
        win:HookScript("OnShow",InstallInviteTranslationHooks)
    end
    SetDB()
    AttachThemeMenu(win)
    RenameSettingsLabel(win)
    ApplyMinimapLogo()
    -- HookScript does NOT call Search() itself. Only the user's click does.
    searchButton:HookScript("OnClick",function()
        if DB and DB.enabledOnSearch then Start(nil,true) end
    end)
    MakeIndicator();UpdateIndicator()
end
local function HookExisting()
    if ForeverQuickJoinTheme and type(ForeverQuickJoinTheme.Attach)=="function"
        and type(hooksecurefunc)=="function" then
        hooksecurefunc(ForeverQuickJoinTheme,"Attach",function(win) Attach(win) end)
    end
    if ForeverQuickJoinTheme and type(hooksecurefunc)=="function" then
        if type(ForeverQuickJoinTheme.Select)=="function" then
            hooksecurefunc(ForeverQuickJoinTheme,"Select",function() ApplyTheme();RenameSettingsLabel() end)
        end
        if type(ForeverQuickJoinTheme.SetTransparency)=="function" then
            hooksecurefunc(ForeverQuickJoinTheme,"SetTransparency",function() ApplyTheme() end)
        elseif type(ForeverQuickJoinTheme.ToggleTransparency)=="function" then
            hooksecurefunc(ForeverQuickJoinTheme,"ToggleTransparency",function() ApplyTheme() end)
        end
    end
    if ForeverQuickJoinTheme and type(ForeverQuickJoinTheme.ApplyNew)=="function"
        and type(hooksecurefunc)=="function" then
            hooksecurefunc(ForeverQuickJoinTheme,"ApplyNew",function()
                RenameSettingsLabel();InstallInviteTranslationHooks()
            end)
    end
    if ForeverQuickJoinLocale and type(ForeverQuickJoinLocale.Select)=="function"
        and type(hooksecurefunc)=="function" then
        hooksecurefunc(ForeverQuickJoinLocale,"Select",function()
            if RefreshIntroLocale then RefreshIntroLocale() end
            if RenameSettingsLabel then RenameSettingsLabel() end
            InstallInviteTranslationHooks()
        end)
    end
    if _G.ForeverQuickJoinWindow then Attach(_G.ForeverQuickJoinWindow) end
    ApplyMinimapLogo()
    if C_LFGList and type(C_LFGList.Search)=="function"
        and type(hooksecurefunc)=="function" then
        -- Passive observation only. Cannot and does not trigger another search.
        local ok=pcall(hooksecurefunc,C_LFGList,"Search",function(cat,_,_,_,_,_,ids)
            local category=Num(cat);local activities={}
            if type(Readable(ids))=="table" then
                for i=1,math.min(#ids,100) do
                    local id=Num(ids[i])
                    if id and id>0 then activities[#activities+1]=id end
                end
            end
            if category and #activities>0 then
                latestSearch={categoryID=category,activityIDs=activities,at=Now()}
            end
        end)
        if not ok then Print("Search parameters cannot be observed; results will still be filtered locally.") end
    end
end

-- MINIMAP: brand-aligned icon on QuickJoin's existing launcher. The base
-- addon's 32x32 minimap button, 20x20 icon and drag/click behavior are intact.
local minimapBranded=false
ApplyMinimapLogo = function()
    if minimapBranded then return end
    local launcher=_G.ForeverQuickJoinMinimapButton
    if not launcher or type(launcher.GetRegions)~="function" then return end
    for _,region in ipairs({launcher:GetRegions()}) do
        if region and type(region.GetObjectType)=="function"
            and region:GetObjectType()=="Texture"
            and type(region.GetTexture)=="function" then
            local texture=region:GetTexture()
            local layer=type(region.GetDrawLayer)=="function" and region:GetDrawLayer() or nil
            local width=type(region.GetWidth)=="function" and region:GetWidth() or nil
            if (type(texture)=="string" and texture:lower():find("inv_misc_grouplooking",1,true))
                or (layer=="BACKGROUND" and type(width)=="number" and width>=18 and width<=22) then
                region:SetTexture("Interface\\AddOns\\ForeverQuickJoin\\Textures\\MinimapLogo.tga")
                region:SetTexCoord(0,1,0,1)
                minimapBranded=true
                return
            end
        end
    end
end

-- The Theme module creates its title region on the main QuickJoin window.
-- Rename the title, not the selected-value display (Forever · EN is useful).
RenameSettingsLabel = function(win)
    win=win or _G.ForeverQuickJoinWindow
    if not win or type(win.GetRegions)~="function" then return end
    for _,region in ipairs({win:GetRegions()}) do
        if region and type(region.GetObjectType)=="function"
            and region:GetObjectType()=="FontString"
            and type(region.GetPoint)=="function" then
            local point,parent,_,x,y=region:GetPoint(1)
            if point=="TOPLEFT" and parent==win
                and type(x)=="number" and math.abs(x-208)<4
                and type(y)=="number" and (math.abs(y+22)<4 or math.abs(y+18)<4) then
                -- Keep enough width for longer translated labels, but align
                -- their right edge 9 px before the dropdown (x=322).
                region:SetText(MonitorCopy("settings"))
                region:SetWidth(105)
                region:SetJustifyH("RIGHT")
                if math.abs(y+18)>=1 then
                    region:ClearAllPoints()
                    region:SetPoint("TOPLEFT",win,"TOPLEFT",208,-18)
                end
                return
            end
        end
    end
end

-- ONE-TIME UPDATE ANNOUNCEMENT ----------------------------------------------
-- Once per feature update unless the player permanently opts out. The same
-- screen can always be reopened from Settings > What's New / Help.
ShowIntro = function(force)
    SetDB()
    if not force and (DB.neverShowAnnouncements or DB.lastIntroVersion==INTRO_VERSION) then return end
    if not intro then
        intro=CreateFrame("Frame","ForeverQuickJoinMonitorWhatsNew",UIParent,"BackdropTemplate")
        -- Room for German/Russian text while keeping the guide lightweight.
        intro:SetSize(565,470)
        intro:SetPoint("CENTER",UIParent,"CENTER",0,55)
        intro:SetFrameStrata("DIALOG");intro:SetFrameLevel(250)
        intro:SetClampedToScreen(true);intro:EnableMouse(true)
        Backdrop(intro)
        intro.labels={}
        local function L(key,x,y,w,h,font)
            local f=Label(intro,"",x,y,w,h,font)
            intro.labels[key]=f
            return f
        end
        intro.title=L("title",20,14,510,23,"GameFontNormalLarge")
        intro.hero=L("hero",20,45,442,32,"GameFontNormalLarge")
        L("lead",20,79,419,42,"GameFontHighlightSmall")
        -- Keep a single illustrative monitor icon; no step-side pictures.
        local art=intro:CreateTexture(nil,"ARTWORK")
        art:SetPoint("TOPRIGHT",intro,"TOPRIGHT",-22,-49)
        art:SetSize(74,74)
        art:SetTexture("Interface\\AddOns\\ForeverQuickJoin\\Textures\\MonitorActive.tga")
        intro.art=art
        L("step1",20,133,525,20,"GameFontNormal")
        L("step1Body",20,155,525,48,"GameFontHighlightSmall")
        L("step2",20,211,525,20,"GameFontNormal")
        L("step2Body",20,233,525,48,"GameFontHighlightSmall")
        L("step3",20,287,525,20,"GameFontNormal")
        L("step3Body",20,310,525,39,"GameFontHighlightSmall")
        intro.controls=L("controls",20,355,525,39,"GameFontHighlightSmall")
        intro.note=L("note",20,395,525,30,"GameFontDisableSmall")
        introNever=CreateFrame("CheckButton",nil,intro,"UICheckButtonTemplate")
        introNever:SetSize(23,23)
        introNever:SetPoint("BOTTOMLEFT",intro,"BOTTOMLEFT",17,11)
        L("never",45,438,338,20,"GameFontHighlightSmall")
        local function Dismiss()
            DB.lastIntroVersion=INTRO_VERSION
            DB.neverShowAnnouncements=introNever:GetChecked()==true
            intro:Hide()
        end
        intro.okButton=Button(intro,"",428,431,116,29,Dismiss)
        intro.okButton.qjPrimary=true
        Button(intro,"X",532,9,21,22,Dismiss)
        intro:Hide()
    end
    introNever:SetChecked(DB.neverShowAnnouncements==true)
    if RefreshIntroLocale then RefreshIntroLocale() end
    intro:Show()
end

M.ShowHelp=function() ShowIntro(true) end

local events=CreateFrame("Frame")
for _,event in ipairs({"PLAYER_LOGIN","LFG_LIST_SEARCH_RESULTS_RECEIVED","LFG_LIST_SEARCH_FAILED",
    "LFG_LIST_SEARCH_RESULT_UPDATED","LFG_LIST_UPDATE_SEARCH_RESULTS",
    "GROUP_ROSTER_UPDATE","GROUP_JOINED","WHO_LIST_UPDATE",
    "CHAT_MSG_CHANNEL","CHAT_MSG_SAY","CHAT_MSG_YELL",
    "PLAYER_REGEN_DISABLED","PLAYER_REGEN_ENABLED",
    "ADDON_ACTION_BLOCKED","ADDON_ACTION_FORBIDDEN"}) do
    events:RegisterEvent(event)
end
events:SetScript("OnEvent",function(_,event,...)
    if event=="PLAYER_LOGIN" then
        SetDB();HookExisting();MakePopup();MakeIndicator();ApplyMinimapLogo()
        if C_Timer and type(C_Timer.After)=="function" then
            C_Timer.After(2,function() ShowIntro(false) end)
        else
            ShowIntro(false)
        end
        if C_Timer and type(C_Timer.NewTicker)=="function" then
            C_Timer.NewTicker(5,function()
                -- Read-only cached status: NEVER call restricted server Search().
                RefreshCachedResults()
                PruneExpiredChat()
                if active then TryAutoJoinLFG(false) end
                if popup and popup:IsShown() then M.RefreshPopup() end
                UpdateIndicator()
            end)
        end
    elseif event=="LFG_LIST_SEARCH_RESULTS_RECEIVED" then
        if active and awaitingResults then
            awaitingResults=false;CaptureSearch()
        end
    elseif event=="LFG_LIST_SEARCH_FAILED" then
        if active and awaitingResults then
            awaitingResults=false
            UpdateIndicator()
            if popup and popup:IsShown() then M.RefreshPopup() end
            Print("Group Finder search failed. Monitor remains on; click Search to retry.")
        end
    elseif event=="LFG_LIST_SEARCH_RESULT_UPDATED" then
        if active then UpdatedResult((...)) end
    elseif event=="LFG_LIST_UPDATE_SEARCH_RESULTS" then
        if active then RefreshCachedResults() end
    elseif event=="GROUP_ROSTER_UPDATE" or event=="GROUP_JOINED" then
        if active then
            local grouped=InGroup()
            if grouped and (not wasGrouped or event=="GROUP_JOINED") then
                M.Stop(false)
                Print("You joined a group. Monitoring stopped.")
            else
                wasGrouped=grouped
            end
        end
    elseif event=="CHAT_MSG_CHANNEL" or event=="CHAT_MSG_SAY"
        or event=="CHAT_MSG_YELL" then
        ReceiveChat(event,...)
    elseif event=="WHO_LIST_UPDATE" then
        ReceiveWho()
    elseif event=="ADDON_ACTION_BLOCKED" or event=="ADDON_ACTION_FORBIDDEN" then
        local addon,detail=...
        if addon==ADDON and (orbSearchAttempt or (Now()-orbSearchAt<2
            and type(detail)=="string" and detail:find("Search",1,true))) then
            awaitingResults=false
            UpdateIndicator()
            Print("WoW blocked the orb Search request. Monitor stays on; use QuickJoin's Search button.")
        end
    elseif event=="PLAYER_REGEN_DISABLED" then
        if active and DB and DB.quietCombat and popup then popup:Hide() end
    elseif event=="PLAYER_REGEN_ENABLED" then
        if active then
            TryAutoJoinLFG(false)
            ShowNext()
        end
    end
end)

SLASH_FOREVERQUICKJOINMONITOR1="/qjm"
SLASH_FOREVERQUICKJOINMONITOR2="/qjmonitor"
SlashCmdList.FOREVERQUICKJOINMONITOR=function(value)
    value=(value or ""):lower():match("^%s*(.-)%s*$")
    if value=="stop" or value=="off" then M.Stop()
    elseif value=="sound on" or value=="sound off" then
        SetDB();DB.sound=value=="sound on"
        Print("Sound "..(DB.sound and "enabled" or "disabled").." (Blizzard PVPEnterQueue).")
    elseif value=="combat on" or value=="combat off" then
        SetDB();DB.quietCombat=value=="combat on"
        Print("Quiet during combat "..(DB.quietCombat and "enabled" or "disabled")..".")
    elseif value=="test" then
        SetDB();DB.enabledOnSearch=true;active=true;awaitingResults=false;verifiedAt=Now()
        scope={categoryID=2,activityIDs={},filters={},advanced={},implicit=true}
        pending={};seen={};current=nil;expanded=false;rosterOffset=0;selectedIndex=1
        MakePopup();MakeIndicator();UpdateIndicator()
        Enqueue({key="test:"..tostring(Now()),synthetic=true,id=nil,
            title="Scarlet Monastery — Cathedral",activity="Scarlet Monastery Cathedral",leader="Demo Leader",
            members=3,cap=5,role="Tank 1   Healer 1   DPS 1",comment="Demo listing — no contact actions will be sent.",
            roster={
                {index=1,name="Demo Leader",class="WARRIOR",className="Warrior",level=35,role="TANK",leader=true},
                {index=2,name="Example Healer",class="PRIEST",className="Priest",level=34,role="HEALER"},
                {index=3,name="Example DPS",class="WARLOCK",className="Warlock",level=36,role="DAMAGER"}}})
    elseif value=="chattest" then
        SetDB();DB.enabledOnSearch=true;active=true;awaitingResults=false
        scope={categoryID=nil,activityIDs={},filters={},advanced={},implicit=true}
        MakePopup();MakeIndicator();UpdateIndicator()
        Enqueue({key="testchat:"..tostring(Now()),chat=true,synthetic=true,id=nil,
            chatKind="LFM",chatChannel="LookingForGroup",chatAt=Now(),
            leader="Demo Recruiter",title="Scarlet Monastery",activity="Scarlet Monastery",
            chatRoles="HEALER, DPS",comment="LFM SM Cath, need healer and 1 DPS — demo only",
            roster={}})
    elseif value=="enable" or value=="disable" then
        SetMonitorEnabled(value=="enable")
        Print("Monitor Mode "..(DB.enabledOnSearch and "enabled" or "disabled").." in Settings.")
    elseif value=="help" then
        ShowIntro(true)
    elseif value=="status" or value=="" then
        Print("Active: "..tostring(active).." · pending: "..#pending
            .." · Group Finder verified: "..(verifiedAt and (math.floor(Now()-verifiedAt).."s ago") or "not yet")
            .." · sources: Group Listings + live LFG Chat"
            .." · chat matches: "..chatMatched)
        Print("LookingForGroup auto-join: "..tostring(ChatAutoJoinOn())
            .." · subscribed: "..tostring(LFGJoined())
            .." · state: "..lfgJoinStatus)
        local sentCount=0
        for _ in pairs(whisperedLeaders) do sentCount=sentCount+1 end
        Print("Whispered this session: "..sentCount.." players; marked on existing Whisper buttons.")
        Print("Commands: /qjm status, stop, test, chattest, help, enable|disable, sound on|off, combat on|off")
    else
        Print("Enable Monitor Mode in Settings, choose filters, and click Search.")
    end
end
