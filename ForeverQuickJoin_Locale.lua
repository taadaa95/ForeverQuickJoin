-- QuickJoin-owned UI localization. Does not modify Blizzard UI or player chat.
local Locale = {}
ForeverQuickJoinLocale = Locale
local LANGS = {enUS=true,frFR=true,deDE=true,esES=true,esMX=true,ptBR=true,ruRU=true,zhCN=true,zhTW=true,koKR=true}
local dict = {
    ["Translate Dungeon Names"]={frFR="Traduire les noms des donjons",deDE="Dungeonnamen übersetzen",esES="Traducir nombres de mazmorras",esMX="Traducir nombres de mazmorras",ptBR="Traduzir nomes das masmorras",ruRU="Переводить названия подземелий",zhCN="翻译地下城名称",zhTW="翻譯地城名稱",koKR="던전 이름 번역"},
    ["Theme / Language:"]={["frFR"]="Thème / Langue :", ["deDE"]="Design / Sprache:", ["esES"]="Tema / Idioma:", ["ptBR"]="Tema / Idioma:", ["ruRU"]="Тема / язык:", ["zhCN"]="主题 / 语言:", ["zhTW"]="主題 / 語言:", ["koKR"]="테마 / 언어:", ["esMX"]="Tema / Idioma:"},
    ["Theme"]={["frFR"]="Thème", ["deDE"]="Design", ["esES"]="Tema", ["ptBR"]="Tema", ["ruRU"]="Тема", ["zhCN"]="主题", ["zhTW"]="主題", ["koKR"]="테마", ["esMX"]="Tema"},
    ["Language"]={["frFR"]="Langue", ["deDE"]="Sprache", ["esES"]="Idioma", ["ptBR"]="Idioma", ["ruRU"]="Язык", ["zhCN"]="语言", ["zhTW"]="語言", ["koKR"]="언어", ["esMX"]="Idioma"},
    ["Automatic (client language)"]={["frFR"]="Automatique (langue du jeu)", ["deDE"]="Automatisch (Spielsprache)", ["esES"]="Automático (idioma del juego)", ["ptBR"]="Automático (idioma do jogo)", ["ruRU"]="Автоматически (язык игры)", ["zhCN"]="自动（游戏语言）", ["zhTW"]="自動（遊戲語言）", ["koKR"]="자동 (게임 언어)", ["esMX"]="Automático (idioma del juego)"},
    ["Transparency"]={["frFR"]="Transparence", ["deDE"]="Transparenz", ["esES"]="Transparencia", ["ptBR"]="Transparência", ["ruRU"]="Прозрачность", ["zhCN"]="透明度", ["zhTW"]="透明度", ["koKR"]="투명도", ["esMX"]="Transparencia"},
    ["Find Groups"]={["frFR"]="Groupes", ["deDE"]="Gruppen", ["esES"]="Buscar grupos", ["ptBR"]="Buscar grupos", ["ruRU"]="Поиск группы", ["zhCN"]="寻找队伍", ["zhTW"]="尋找隊伍", ["koKR"]="파티 찾기", ["esMX"]="Buscar grupos"},
    ["List Group"]={["frFR"]="Créer groupe", ["deDE"]="Gruppe anbieten", ["esES"]="Crear grupo", ["ptBR"]="Criar grupo", ["ruRU"]="Создать", ["zhCN"]="创建队伍", ["zhTW"]="建立隊伍", ["koKR"]="파티 만들기", ["esMX"]="Crear grupo"},
    ["Applications"]={["frFR"]="Demandes", ["deDE"]="Bewerbungen", ["esES"]="Solicitudes", ["ptBR"]="Solicitações", ["ruRU"]="Заявки", ["zhCN"]="申请", ["zhTW"]="申請", ["koKR"]="신청", ["esMX"]="Solicitudes"},
    ["Group Listings"]={["frFR"]="Annonces de groupe", ["deDE"]="Gruppenangebote", ["esES"]="Anuncios de grupo", ["ptBR"]="Anúncios de grupos", ["ruRU"]="Объявления групп", ["zhCN"]="队伍列表", ["zhTW"]="隊伍列表", ["koKR"]="파티 목록", ["esMX"]="Anuncios de grupo"},
    ["LFG Chat"]={["frFR"]="Chat RdG", ["deDE"]="LFG-Chat", ["esES"]="Chat de grupos", ["ptBR"]="Chat de grupos", ["ruRU"]="Чат поиска", ["zhCN"]="组队聊天", ["zhTW"]="組隊聊天", ["koKR"]="파티 찾기 채팅", ["esMX"]="Chat de grupos"},
    ["My Applications"]={["frFR"]="Mes demandes", ["deDE"]="Meine Bewerbungen", ["esES"]="Mis solicitudes", ["ptBR"]="Minhas solicitações", ["ruRU"]="Мои заявки", ["zhCN"]="我的申请", ["zhTW"]="我的申請", ["koKR"]="내 신청", ["esMX"]="Mis solicitudes"},
    ["Search"]={["frFR"]="Rechercher", ["deDE"]="Suchen", ["esES"]="Buscar", ["ptBR"]="Pesquisar", ["ruRU"]="Поиск", ["zhCN"]="搜索", ["zhTW"]="搜尋", ["koKR"]="검색", ["esMX"]="Buscar"},
    ["Advanced Filters >>"]={["frFR"]="Filtres avancés >>", ["deDE"]="Erweiterte Filter >>", ["esES"]="Filtros avanzados >>", ["ptBR"]="Filtros avançados >>", ["ruRU"]="Доп. фильтры >>", ["zhCN"]="高级筛选 >>", ["zhTW"]="進階篩選 >>", ["koKR"]="고급 필터 >>", ["esMX"]="Filtros avanzados >>"},
    ["Advanced Filters"]={["frFR"]="Filtres avancés", ["deDE"]="Erweiterte Filter", ["esES"]="Filtros avanzados", ["ptBR"]="Filtros avançados", ["ruRU"]="Доп. фильтры", ["zhCN"]="高级筛选", ["zhTW"]="進階篩選", ["koKR"]="고급 필터", ["esMX"]="Filtros avanzados"},
    ["ADVANCED FILTERS"]={["frFR"]="FILTRES AVANCÉS", ["deDE"]="ERWEITERTE FILTER", ["esES"]="FILTROS AVANZADOS", ["ptBR"]="FILTROS AVANÇADOS", ["ruRU"]="ДОП. ФИЛЬТРЫ", ["zhCN"]="高级筛选", ["zhTW"]="進階篩選", ["koKR"]="고급 필터", ["esMX"]="FILTROS AVANZADOS"},
    ["GROUP LISTINGS"]={["frFR"]="ANNONCES DE GROUPE", ["deDE"]="GRUPPENANGEBOTE", ["esES"]="ANUNCIOS DE GRUPO", ["ptBR"]="ANÚNCIOS DE GRUPOS", ["ruRU"]="ОБЪЯВЛЕНИЯ", ["zhCN"]="队伍列表", ["zhTW"]="隊伍列表", ["koKR"]="파티 목록", ["esMX"]="ANUNCIOS DE GRUPO"},
    ["LEADER"]={["frFR"]="CHEF", ["deDE"]="LEITER", ["esES"]="LÍDER", ["ptBR"]="LÍDER", ["ruRU"]="ЛИДЕР", ["zhCN"]="队长", ["zhTW"]="隊長", ["koKR"]="파티장", ["esMX"]="LÍDER"},
    ["ACTIVITY / PLAYSTYLE"]={["frFR"]="ACTIVITÉ / STYLE", ["deDE"]="AKTIVITÄT / STIL", ["esES"]="ACTIVIDAD / ESTILO", ["ptBR"]="ATIVIDADE / ESTILO", ["ruRU"]="АКТИВНОСТЬ / СТИЛЬ", ["zhCN"]="活动 / 风格", ["zhTW"]="活動 / 風格", ["koKR"]="활동 / 스타일", ["esMX"]="ACTIVIDAD / ESTILO"},
    ["GROUP ROLES"]={["frFR"]="RÔLES", ["deDE"]="GRUPPENROLLEN", ["esES"]="ROLES DEL GRUPO", ["ptBR"]="FUNÇÕES DO GRUPO", ["ruRU"]="РОЛИ ГРУППЫ", ["zhCN"]="队伍职责", ["zhTW"]="隊伍職責", ["koKR"]="파티 역할", ["esMX"]="ROLES DEL GRUPO"},
    ["Whisper to Join"]={["frFR"]="Murmurer", ["deDE"]="Flüstern", ["esES"]="Susurrar", ["ptBR"]="Sussurrar", ["ruRU"]="Шепнуть", ["zhCN"]="密语加入", ["zhTW"]="密語加入", ["koKR"]="귓속말", ["esMX"]="Susurrar"},
    ["Invite"]={["frFR"]="Inviter", ["deDE"]="Einladen", ["esES"]="Invitar", ["ptBR"]="Convidar", ["ruRU"]="Пригласить", ["zhCN"]="邀请", ["zhTW"]="邀請", ["koKR"]="초대", ["esMX"]="Invitar"},
    ["Inviting..."]={["frFR"]="En cours...", ["deDE"]="Lädt ein...", ["esES"]="Invitando...", ["ptBR"]="Convidando...", ["ruRU"]="Приглашаем...", ["zhCN"]="邀请中...", ["zhTW"]="邀請中...", ["koKR"]="초대 중...", ["esMX"]="Invitando..."},
    ["Invite Sent"]={["frFR"]="Envoyée", ["deDE"]="Gesendet", ["esES"]="Enviada", ["ptBR"]="Enviado", ["ruRU"]="Отправлено", ["zhCN"]="已发送邀请", ["zhTW"]="已發送邀請", ["koKR"]="초대 전송됨", ["esMX"]="Enviada"},
    ["W sent"]={["frFR"]="Envoyé", ["deDE"]="Gesendet", ["esES"]="Enviado", ["ptBR"]="Enviado", ["ruRU"]="Отправлено", ["zhCN"]="密语已发", ["zhTW"]="密語已發", ["koKR"]="귓속말 보냄", ["esMX"]="Enviado"},
    ["Unconfirmed"]={["frFR"]="Non confirmé", ["deDE"]="Unbestätigt", ["esES"]="Sin confirmar", ["ptBR"]="Não confirmado", ["ruRU"]="Не подтверждено", ["zhCN"]="未确认", ["zhTW"]="未確認", ["koKR"]="미확인", ["esMX"]="Sin confirmar"},
    ["Failed"]={["frFR"]="Échec", ["deDE"]="Fehlgeschlagen", ["esES"]="Error", ["ptBR"]="Falhou", ["ruRU"]="Ошибка", ["zhCN"]="失败", ["zhTW"]="失敗", ["koKR"]="실패", ["esMX"]="Error"},
    ["Joined"]={["frFR"]="Rejoint", ["deDE"]="Beigetreten", ["esES"]="Unido", ["ptBR"]="Entrou", ["ruRU"]="Вступил", ["zhCN"]="已加入", ["zhTW"]="已加入", ["koKR"]="참여 완료", ["esMX"]="Unido"},
    ["Newer"]={["frFR"]="Plus récent", ["deDE"]="Neuer", ["esES"]="Más reciente", ["ptBR"]="Mais recente", ["ruRU"]="Новее", ["zhCN"]="较新", ["zhTW"]="較新", ["koKR"]="최신", ["esMX"]="Más reciente"},
    ["Older"]={["frFR"]="Plus ancien", ["deDE"]="Älter", ["esES"]="Más antiguo", ["ptBR"]="Mais antigo", ["ruRU"]="Старее", ["zhCN"]="较旧", ["zhTW"]="較舊", ["koKR"]="이전", ["esMX"]="Más antiguo"},
    ["All"]={["frFR"]="Tout", ["deDE"]="Alle", ["esES"]="Todos", ["ptBR"]="Todos", ["ruRU"]="Все", ["zhCN"]="全部", ["zhTW"]="全部", ["koKR"]="전체", ["esMX"]="Todos"},
    ["Diagnostics"]={["frFR"]="Diagnostic", ["deDE"]="Diagnose", ["esES"]="Diagnóstico", ["ptBR"]="Diagnóstico", ["ruRU"]="Диагностика", ["zhCN"]="诊断", ["zhTW"]="診斷", ["koKR"]="진단", ["esMX"]="Diagnóstico"},
    ["Reply"]={["frFR"]="Répondre", ["deDE"]="Antworten", ["esES"]="Responder", ["ptBR"]="Responder", ["ruRU"]="Ответить", ["zhCN"]="回复", ["zhTW"]="回覆", ["koKR"]="답장", ["esMX"]="Responder"},
    ["Reply to leader"]={["frFR"]="Répondre au chef", ["deDE"]="Leiter antworten", ["esES"]="Responder al líder", ["ptBR"]="Responder ao líder", ["ruRU"]="Ответить лидеру", ["zhCN"]="回复队长", ["zhTW"]="回覆隊長", ["koKR"]="파티장에게 답장", ["esMX"]="Responder al líder"},
    ["Review / Fix Roles"]={["frFR"]="Vérifier les rôles", ["deDE"]="Rollen prüfen", ["esES"]="Revisar roles", ["ptBR"]="Revisar funções", ["ruRU"]="Проверить роли", ["zhCN"]="检查职责", ["zhTW"]="檢查職責", ["koKR"]="역할 확인", ["esMX"]="Revisar roles"},
    ["Change Roles"]={["frFR"]="Modifier les rôles", ["deDE"]="Rollen ändern", ["esES"]="Cambiar roles", ["ptBR"]="Mudar funções", ["ruRU"]="Сменить роли", ["zhCN"]="更改职责", ["zhTW"]="變更職責", ["koKR"]="역할 변경", ["esMX"]="Cambiar roles"},
    ["PARTY ROLE MANAGER"]={["frFR"]="GESTION DES RÔLES", ["deDE"]="ROLLENVERWALTUNG", ["esES"]="GESTOR DE ROLES", ["ptBR"]="GERENCIAR FUNÇÕES", ["ruRU"]="УПРАВЛЕНИЕ РОЛЯМИ", ["zhCN"]="队伍职责管理", ["zhTW"]="隊伍職責管理", ["koKR"]="파티 역할 관리", ["esMX"]="GESTOR DE ROLES"},
    ["Party detected"]={["frFR"]="Groupe détecté", ["deDE"]="Gruppe erkannt", ["esES"]="Grupo detectado", ["ptBR"]="Grupo detectado", ["ruRU"]="Группа обнаружена", ["zhCN"]="检测到队伍", ["zhTW"]="偵測到隊伍", ["koKR"]="파티 감지", ["esMX"]="Grupo detectado"},
    ["Close"]={["frFR"]="Fermer", ["deDE"]="Schließen", ["esES"]="Cerrar", ["ptBR"]="Fechar", ["ruRU"]="Закрыть", ["zhCN"]="关闭", ["zhTW"]="關閉", ["koKR"]="닫기", ["esMX"]="Cerrar"},
    ["Tank"]={["esES"]="Tanque", ["ptBR"]="Tanque", ["ruRU"]="Танк", ["zhCN"]="坦克", ["zhTW"]="坦克", ["koKR"]="탱커", ["esMX"]="Tanque"},
    ["Healer"]={["frFR"]="Soigneur", ["deDE"]="Heiler", ["esES"]="Sanador", ["ptBR"]="Curandeiro", ["ruRU"]="Лекарь", ["zhCN"]="治疗", ["zhTW"]="治療", ["koKR"]="힐러", ["esMX"]="Sanador"},
    ["DPS"]={["ruRU"]="ДД", ["zhCN"]="输出", ["zhTW"]="輸出", ["koKR"]="딜러"},
    ["Unknown"]={["frFR"]="Inconnu", ["deDE"]="Unbekannt", ["esES"]="Desconocido", ["ptBR"]="Desconhecido", ["ruRU"]="Неизвестно", ["zhCN"]="未知", ["zhTW"]="未知", ["koKR"]="알 수 없음", ["esMX"]="Desconocido"},
    ["Auto"]={["ruRU"]="Авто", ["zhCN"]="自动", ["zhTW"]="自動", ["koKR"]="자동"},
    ["Unassigned"]={["frFR"]="Non attribué", ["deDE"]="Nicht zugewiesen", ["esES"]="Sin asignar", ["ptBR"]="Não atribuído", ["ruRU"]="Не назначено", ["zhCN"]="未分配", ["zhTW"]="未分配", ["koKR"]="미배정", ["esMX"]="Sin asignar"},
    ["Solo"]={["ruRU"]="Один", ["zhCN"]="单人", ["zhTW"]="單人", ["koKR"]="솔로"},
    ["Group Description"]={["frFR"]="Description du groupe", ["deDE"]="Gruppenbeschreibung", ["esES"]="Descripción del grupo", ["ptBR"]="Descrição do grupo", ["ruRU"]="Описание группы", ["zhCN"]="队伍说明", ["zhTW"]="隊伍說明", ["koKR"]="파티 설명", ["esMX"]="Descripción del grupo"},
    ["Prepare /who"]={["frFR"]="Préparer /who", ["deDE"]="/who vorbereiten", ["esES"]="Preparar /who", ["ptBR"]="Preparar /who", ["ruRU"]="Подготовить /who", ["zhCN"]="准备 /who", ["zhTW"]="準備 /who", ["koKR"]="/who 준비", ["esMX"]="Preparar /who"},
    ["Prepare Whisper"]={["frFR"]="Préparer un murmure", ["deDE"]="Flüstern vorbereiten", ["esES"]="Preparar susurro", ["ptBR"]="Preparar sussurro", ["ruRU"]="Подготовить шёпот", ["zhCN"]="准备密语", ["zhTW"]="準備密語", ["koKR"]="귓속말 준비", ["esMX"]="Preparar susurro"},
    ["Activities / zones..."]={["frFR"]="Activités / zones...", ["deDE"]="Aktivitäten / Gebiete...", ["esES"]="Actividades / zonas...", ["ptBR"]="Atividades / zonas...", ["ruRU"]="Активности / зоны...", ["zhCN"]="活动 / 区域...", ["zhTW"]="活動 / 區域...", ["koKR"]="활동 / 지역...", ["esMX"]="Actividades / zonas..."},
    ["Show all level ranges"]={["frFR"]="Afficher tous les niveaux", ["deDE"]="Alle Stufenbereiche", ["esES"]="Mostrar todos los niveles", ["ptBR"]="Mostrar todos os níveis", ["ruRU"]="Все уровни", ["zhCN"]="显示所有等级", ["zhTW"]="顯示所有等級", ["koKR"]="모든 레벨 보기", ["esMX"]="Mostrar todos los niveles"},
    ["Sort by:"]={["frFR"]="Trier par :", ["deDE"]="Sortieren nach:", ["esES"]="Ordenar por:", ["ptBR"]="Ordenar por:", ["ruRU"]="Сортировать:", ["zhCN"]="排序：", ["zhTW"]="排序：", ["koKR"]="정렬:", ["esMX"]="Ordenar por:"},
    ["Space for:"]={["frFR"]="Place pour :", ["deDE"]="Platz für:", ["esES"]="Plazas para:", ["ptBR"]="Vagas para:", ["ruRU"]="Места для:", ["zhCN"]="空位：", ["zhTW"]="空位：", ["koKR"]="모집 역할:", ["esMX"]="Plazas para:"},
    ["Already has:"]={["frFR"]="A déjà :", ["deDE"]="Bereits dabei:", ["esES"]="Ya tiene:", ["ptBR"]="Já tem:", ["ruRU"]="Уже есть:", ["zhCN"]="已有：", ["zhTW"]="已有：", ["koKR"]="보유 역할:", ["esMX"]="Ya tiene:"},
    ["Ignore team composition"]={["frFR"]="Ignorer la composition", ["deDE"]="Gruppenaufbau ignorieren", ["esES"]="Ignorar composición", ["ptBR"]="Ignorar composição", ["ruRU"]="Игнорировать состав", ["zhCN"]="忽略队伍配置", ["zhTW"]="忽略隊伍配置", ["koKR"]="파티 구성 무시", ["esMX"]="Ignorar composición"},
    ["Max members:"]={["frFR"]="Membres max. :", ["deDE"]="Max. Mitglieder:", ["esES"]="Máx. miembros:", ["ptBR"]="Máx. membros:", ["ruRU"]="Макс. участников:", ["zhCN"]="最多人数：", ["zhTW"]="最多人數：", ["koKR"]="최대 인원:", ["esMX"]="Máx. miembros:"},
    ["Only groups I can whisper"]={["frFR"]="Groupes contactables seulement", ["deDE"]="Nur erreichbare Gruppen", ["esES"]="Solo grupos contactables", ["ptBR"]="Só grupos contactáveis", ["ruRU"]="Только доступные группы", ["zhCN"]="仅可密语队伍", ["zhTW"]="僅可密語隊伍", ["koKR"]="귓속말 가능한 파티만", ["esMX"]="Solo grupos contactables"},
    ["Only groups with descriptions"]={["frFR"]="Avec description seulement", ["deDE"]="Nur mit Beschreibung", ["esES"]="Solo con descripción", ["ptBR"]="Só com descrição", ["ruRU"]="Только с описанием", ["zhCN"]="仅有描述的队伍", ["zhTW"]="僅有說明的隊伍", ["koKR"]="설명 있는 파티만", ["esMX"]="Solo con descripción"},
    ["Clear All Filters"]={["frFR"]="Effacer tous les filtres", ["deDE"]="Alle Filter löschen", ["esES"]="Borrar filtros", ["ptBR"]="Limpar filtros", ["ruRU"]="Сбросить фильтры", ["zhCN"]="清除筛选", ["zhTW"]="清除篩選", ["koKR"]="필터 초기화", ["esMX"]="Borrar filtros"},
    ["MY APPLICATIONS"]={["frFR"]="MES DEMANDES", ["deDE"]="MEINE BEWERBUNGEN", ["esES"]="MIS SOLICITUDES", ["ptBR"]="MINHAS SOLICITAÇÕES", ["ruRU"]="МОИ ЗАЯВКИ", ["zhCN"]="我的申请", ["zhTW"]="我的申請", ["koKR"]="내 신청", ["esMX"]="MIS SOLICITUDES"},
    ["APPLICANT INBOX"]={["frFR"]="DEMANDES REÇUES", ["deDE"]="BEWERBER-POSTEINGANG", ["esES"]="SOLICITUDES RECIBIDAS", ["ptBR"]="SOLICITAÇÕES RECEBIDAS", ["ruRU"]="ЗАЯВКИ", ["zhCN"]="申请收件箱", ["zhTW"]="申請收件匣", ["koKR"]="신청자 목록", ["esMX"]="SOLICITUDES RECIBIDAS"},
    ["Open Blizzard Listing"]={["frFR"]="Ouvrir annonce Blizzard", ["deDE"]="Blizzard-Anzeige öffnen", ["esES"]="Abrir anuncio Blizzard", ["ptBR"]="Abrir anúncio Blizzard", ["ruRU"]="Открыть объявление Blizzard", ["zhCN"]="打开暴雪队伍列表", ["zhTW"]="開啟暴雪隊伍列表", ["koKR"]="블리자드 목록 열기", ["esMX"]="Abrir anuncio Blizzard"},
    ["No active listing"]={["frFR"]="Aucune annonce active", ["deDE"]="Kein aktives Angebot", ["esES"]="Sin anuncio activo", ["ptBR"]="Nenhum anúncio ativo", ["ruRU"]="Нет активного объявления", ["zhCN"]="无活跃招募", ["zhTW"]="無進行中招募", ["koKR"]="활성 모집 없음", ["esMX"]="Sin anuncio activo"},
    ["Manage incoming whispers and applicants here."]={["frFR"]="Gérez ici les murmures et demandes.", ["deDE"]="Hier Flüstern und Bewerbungen verwalten.", ["esES"]="Gestiona aquí susurros y solicitudes.", ["ptBR"]="Gerencie sussurros e solicitações aqui.", ["esMX"]="Gestiona aquí susurros y solicitudes."},
    ["No applicant selected"]={["frFR"]="Aucun candidat sélectionné", ["deDE"]="Kein Bewerber ausgewählt", ["esES"]="Sin candidato seleccionado", ["ptBR"]="Nenhum candidato selecionado", ["esMX"]="Sin candidato seleccionado"},
    ["Assign role:"]={["frFR"]="Attribuer un rôle :", ["deDE"]="Rolle zuweisen:", ["esES"]="Asignar rol:", ["ptBR"]="Atribuir função:", ["esMX"]="Asignar rol:"},
    ["WHISPER CONVERSATION (selected player only)"]={["frFR"]="CONVERSATION (joueur sélectionné)", ["deDE"]="FLÜSTER-CHAT (ausgewählt)", ["esES"]="CONVERSACIÓN (seleccionado)", ["ptBR"]="CONVERSA (selecionado)", ["esMX"]="CONVERSACIÓN (seleccionado)"},
    ["Decline + Remove"]={["frFR"]="Refuser et retirer", ["deDE"]="Ablehnen + entfernen", ["esES"]="Rechazar y eliminar", ["ptBR"]="Recusar e remover", ["esMX"]="Rechazar y eliminar"},
    ["Dismiss"]={["frFR"]="Retirer", ["deDE"]="Schließen", ["esES"]="Descartar", ["ptBR"]="Dispensar", ["esMX"]="Descartar"},
    ["Lookup /who"]={["frFR"]="Chercher /who", ["deDE"]="/who suchen", ["esES"]="Buscar /who", ["ptBR"]="Buscar /who", ["esMX"]="Buscar /who"},
    ["CONTACTED GROUPS (0)"]={["frFR"]="GROUPES CONTACTÉS (0)", ["deDE"]="KONTAKTIERTE GRUPPEN (0)", ["esES"]="GRUPOS CONTACTADOS (0)", ["ptBR"]="GRUPOS CONTATADOS (0)", ["esMX"]="GRUPOS CONTACTADOS (0)"},
    ["Select a contacted group"]={["frFR"]="Choisissez un groupe contacté", ["deDE"]="Kontaktierte Gruppe wählen", ["esES"]="Selecciona un grupo", ["ptBR"]="Selecione um grupo", ["esMX"]="Selecciona un grupo"},
    ["Reply notifications"]={["frFR"]="Notifications de réponse", ["deDE"]="Antwortbenachrichtigung", ["esES"]="Avisos de respuestas", ["ptBR"]="Avisos de respostas", ["esMX"]="Avisos de respuestas"},
    ["Reply prepares chat; press Enter to send."]={["frFR"]="Le chat s’ouvre ; Entrée pour envoyer.", ["deDE"]="Chat vorbereitet; Enter zum Senden.", ["esES"]="Chat preparado; Enter para enviar.", ["ptBR"]="Chat preparado; Enter para enviar.", ["esMX"]="Chat preparado; Enter para enviar."},
    ["Not in Finder means unverified; it does not prove the group disbanded."]={["frFR"]="Absent du Finder = non vérifié, pas forcément dissous.", ["deDE"]="Nicht im Finder heißt unbestätigt, nicht aufgelöst.", ["esES"]="Fuera del buscador no implica disolución.", ["ptBR"]="Fora do buscador não implica dissolução.", ["esMX"]="Fuera del buscador no implica disolución."},
    ["MANAGE LISTING"]={["frFR"]="GÉRER L’ANNONCE", ["deDE"]="GRUPPE VERWALTEN", ["esES"]="GESTIONAR ANUNCIO", ["ptBR"]="GERENCIAR ANÚNCIO", ["esMX"]="GESTIONAR ANUNCIO"},
    ["CATEGORY"]={["frFR"]="CATÉGORIE", ["deDE"]="KATEGORIE", ["esES"]="CATEGORÍA", ["ptBR"]="CATEGORIA", ["esMX"]="CATEGORÍA"},
    ["FILTER ACTIVITIES"]={["frFR"]="FILTRER LES ACTIVITÉS", ["deDE"]="AKTIVITÄTEN FILTERN", ["esES"]="FILTRAR ACTIVIDADES", ["ptBR"]="FILTRAR ATIVIDADES", ["esMX"]="FILTRAR ACTIVIDADES"},
    ["PLAYSTYLE"]={["frFR"]="STYLE DE JEU", ["deDE"]="SPIELSTIL", ["esES"]="ESTILO DE JUEGO", ["ptBR"]="ESTILO DE JOGO", ["esMX"]="ESTILO DE JUEGO"},
    ["Selected activities"]={["frFR"]="Activités sélectionnées", ["deDE"]="Gewählte Aktivitäten", ["esES"]="Actividades elegidas", ["ptBR"]="Atividades selecionadas", ["esMX"]="Actividades elegidas"},
    ["Clear selection"]={["frFR"]="Effacer la sélection", ["deDE"]="Auswahl löschen", ["esES"]="Borrar selección", ["ptBR"]="Limpar seleção", ["esMX"]="Borrar selección"},
    ["Refresh activities"]={["frFR"]="Actualiser les activités", ["deDE"]="Aktivitäten aktualisieren", ["esES"]="Actualizar actividades", ["ptBR"]="Atualizar atividades", ["esMX"]="Actualizar actividades"},
    ["Create"]={["frFR"]="Créer", ["deDE"]="Erstellen", ["esES"]="Crear", ["ptBR"]="Criar", ["esMX"]="Crear"},
    ["Update"]={["frFR"]="Modifier", ["deDE"]="Aktualisieren", ["esES"]="Actualizar", ["ptBR"]="Atualizar", ["esMX"]="Actualizar"},
    ["Delist"]={["frFR"]="Retirer", ["deDE"]="Entfernen", ["esES"]="Quitar anuncio", ["ptBR"]="Remover anúncio", ["esMX"]="Quitar anuncio"},
    ["Back to Listings"]={["frFR"]="Retour aux annonces", ["deDE"]="Zurück zu Angeboten", ["esES"]="Volver a anuncios", ["ptBR"]="Voltar aos anúncios", ["esMX"]="Volver a anuncios"},
    ["Applicants"]={["frFR"]="Candidats", ["deDE"]="Bewerber", ["esES"]="Candidatos", ["ptBR"]="Candidatos", ["esMX"]="Candidatos"},
    ["New-player friendly"]={["frFR"]="Débutants bienvenus", ["deDE"]="Anfängerfreundlich", ["esES"]="Apto para principiantes", ["ptBR"]="Aceita iniciantes", ["esMX"]="Apto para principiantes"},
    ["DESCRIPTION  (BLIZZARD'S ORIGINAL EDITOR)"]={["frFR"]="DESCRIPTION (ÉDITEUR BLIZZARD)", ["deDE"]="BESCHREIBUNG (BLIZZARD-EDITOR)", ["esES"]="DESCRIPCIÓN (EDITOR BLIZZARD)", ["ptBR"]="DESCRIÇÃO (EDITOR BLIZZARD)", ["esMX"]="DESCRIPCIÓN (EDITOR BLIZZARD)"},
    ["Click in the field below and type normally:"]={["frFR"]="Cliquez ci-dessous pour écrire :", ["deDE"]="Unten klicken und normal schreiben:", ["esES"]="Haz clic abajo y escribe:", ["ptBR"]="Clique abaixo e digite:", ["esMX"]="Haz clic abajo y escribe:"},
    ["Refit Editor"]={["frFR"]="Ajuster l’éditeur", ["deDE"]="Editor anpassen", ["esES"]="Ajustar editor", ["ptBR"]="Ajustar editor", ["esMX"]="Ajustar editor"},
    ["Previous"]={["frFR"]="Précédent", ["deDE"]="Zurück", ["esES"]="Anterior", ["ptBR"]="Anterior", ["esMX"]="Anterior"},
    ["Next"]={["frFR"]="Suivant", ["deDE"]="Weiter", ["esES"]="Siguiente", ["ptBR"]="Próximo", ["esMX"]="Siguiente"},
    ["Reload Whisper Template"]={["frFR"]="Réinitialiser le murmure", ["deDE"]="Flüstervorlage zurücksetzen", ["esES"]="Restablecer plantilla", ["ptBR"]="Recarregar modelo", ["esMX"]="Restablecer plantilla"},
    ["Preview:"]={["frFR"]="Aperçu :", ["deDE"]="Vorschau:", ["esES"]="Vista previa:", ["ptBR"]="Prévia:", ["esMX"]="Vista previa:"},
    ["Waiting for activities..."]={["frFR"]="Chargement des activités...", ["deDE"]="Warte auf Aktivitäten...", ["esES"]="Esperando actividades...", ["ptBR"]="Aguardando atividades...", ["esMX"]="Esperando actividades..."},
    ["Roles unspecified"]={["frFR"]="Rôles non précisés", ["deDE"]="Rollen unbekannt", ["esES"]="Roles sin especificar", ["ptBR"]="Funções não informadas", ["esMX"]="Roles sin especificar"},
    ["LFG CHAT — recruitment posts seen by your character"]={["frFR"]="CHAT RdG — annonces reçues en jeu", ["deDE"]="LFG-CHAT — empfangene Gruppensuche", ["esES"]="CHAT DE GRUPOS — mensajes recibidos", ["ptBR"]="CHAT DE GRUPOS — mensagens recebidas", ["esMX"]="CHAT DE GRUPOS — mensajes recibidos"},
    ["LFG Chat listening for public messages..."]={["frFR"]="Chat RdG : écoute des messages publics...", ["deDE"]="LFG-Chat: öffentliche Nachrichten werden gelesen...", ["esES"]="Chat de grupos: escuchando mensajes...", ["ptBR"]="Chat de grupos: recebendo mensagens...", ["esMX"]="Chat de grupos: escuchando mensajes..."},
    ["Search retrieves groups on click. Filters and sorting are in Advanced Filters."]={["frFR"]="Cliquez sur Rechercher. Filtres et tri dans Filtres avancés.", ["deDE"]="Suche per Klick; Filter und Sortierung unter Erweiterte Filter.", ["esES"]="Pulsa Buscar. Filtros y orden en Filtros avanzados.", ["ptBR"]="Clique Pesquisar. Filtros em Filtros avançados.", ["esMX"]="Pulsa Buscar. Filtros y orden en Filtros avanzados."},
    ["No cached listings yet. Select an activity and click Search."]={["frFR"]="Aucune annonce en cache. Choisissez une activité et recherchez.", ["deDE"]="Noch keine Angebote. Aktivität wählen und suchen.", ["esES"]="Sin anuncios guardados. Elige actividad y busca.", ["ptBR"]="Sem anúncios. Escolha uma atividade e pesquise.", ["esMX"]="Sin anuncios guardados. Elige actividad y busca."},
    ["No public messages yet."]={["frFR"]="Aucun message public pour le moment.", ["deDE"]="Noch keine öffentlichen Nachrichten.", ["esES"]="Todavía no hay mensajes públicos.", ["ptBR"]="Ainda não há mensagens públicas.", ["esMX"]="Todavía no hay mensajes públicos."},
    ["Create Listing"]={["frFR"]="Créer annonce", ["deDE"]="Angebot erstellen", ["esES"]="Crear grupo", ["ptBR"]="Criar grupo", ["ruRU"]="Создать группу", ["zhCN"]="创建队伍", ["zhTW"]="建立隊伍", ["koKR"]="파티 생성", ["esMX"]="Crear grupo"},
    ["Dungeons"]={["frFR"]="Donjons", ["deDE"]="Dungeons", ["esES"]="Mazmorras", ["ptBR"]="Masmorras", ["ruRU"]="Подземелья", ["zhCN"]="地下城", ["zhTW"]="地城", ["koKR"]="던전", ["esMX"]="Mazmorras"},
    ["All activities"]={["frFR"]="Toutes les activités", ["deDE"]="Alle Aktivitäten", ["esES"]="Todas las actividades", ["ptBR"]="Todas as atividades", ["ruRU"]="Все занятия", ["zhCN"]="所有活动", ["zhTW"]="所有活動", ["koKR"]="모든 활동", ["esMX"]="Todas las actividades"},
    ["All categories"]={["frFR"]="Toutes les catégories", ["deDE"]="Alle Kategorien", ["esES"]="Todas las categorías", ["ptBR"]="Todas as categorias", ["ruRU"]="Все категории", ["zhCN"]="所有类别", ["zhTW"]="所有類別", ["koKR"]="모든 범주", ["esMX"]="Todas las categorías"},
    ["Category"]={["frFR"]="Catégorie", ["deDE"]="Kategorie", ["esES"]="Categoría", ["ptBR"]="Categoria", ["ruRU"]="Категория", ["zhCN"]="类别", ["zhTW"]="類別", ["koKR"]="범주", ["esMX"]="Categoría"},
    ["Roles confirmed"]={["frFR"]="Rôles confirmés", ["deDE"]="Rollen bestätigt", ["esES"]="Roles confirmados", ["ptBR"]="Funções confirmadas", ["ruRU"]="Роли подтверждены", ["zhCN"]="职责已确认", ["zhTW"]="職責已確認", ["koKR"]="역할 확인됨", ["esMX"]="Roles confirmados"},
    ["Current character"]={["frFR"]="Personnage actuel", ["deDE"]="Aktueller Charakter", ["esES"]="Personaje actual", ["ptBR"]="Personagem atual", ["ruRU"]="Текущий персонаж", ["zhCN"]="当前角色", ["zhTW"]="目前角色", ["koKR"]="현재 캐릭터", ["esMX"]="Personaje actual"},
    ["Showing"]={["frFR"]="Affichage", ["deDE"]="Anzeige", ["esES"]="Mostrando", ["ptBR"]="Exibindo", ["ruRU"]="Показано", ["zhCN"]="显示", ["zhTW"]="顯示", ["koKR"]="표시", ["esMX"]="Mostrando"},
    ["Group Finder listing"]={["frFR"]="Annonce de groupe", ["deDE"]="Gruppenangebot", ["esES"]="Anuncio de grupo", ["ptBR"]="Anúncio de grupo", ["ruRU"]="Объявление группы", ["zhCN"]="队伍信息", ["zhTW"]="隊伍資訊", ["koKR"]="파티 목록", ["esMX"]="Anuncio de grupo"},
    ["Activity:"]={["frFR"]="Activité :", ["deDE"]="Aktivität:", ["esES"]="Actividad:", ["ptBR"]="Atividade:", ["ruRU"]="Активность:", ["zhCN"]="活动：", ["zhTW"]="活動：", ["koKR"]="활동:", ["esMX"]="Actividad:"},
    ["Activities:"]={["frFR"]="Activités :", ["deDE"]="Aktivitäten:", ["esES"]="Actividades:", ["ptBR"]="Atividades:", ["ruRU"]="Активности:", ["zhCN"]="活动：", ["zhTW"]="活動：", ["koKR"]="활동:", ["esMX"]="Actividades:"},
    ["Expired listing"]={["frFR"]="Annonce expirée", ["deDE"]="Abgelaufenes Angebot", ["esES"]="Anuncio caducado", ["ptBR"]="Anúncio expirado", ["ruRU"]="Объявление устарело", ["zhCN"]="过期队伍", ["zhTW"]="過期隊伍", ["koKR"]="만료된 파티", ["esMX"]="Anuncio caducado"},
    ["Member information is not available for this listing."]={["frFR"]="Informations des membres indisponibles.", ["deDE"]="Mitgliederinformationen nicht verfügbar.", ["esES"]="Información de miembros no disponible.", ["ptBR"]="Dados dos membros indisponíveis.", ["ruRU"]="Информация об участниках недоступна.", ["zhCN"]="无成员信息", ["zhTW"]="無成員資訊", ["koKR"]="멤버 정보 없음", ["esMX"]="Información de miembros no disponible."},
    ["Area unknown"]={["frFR"]="Zone inconnue", ["deDE"]="Gebiet unbekannt", ["esES"]="Zona desconocida", ["ptBR"]="Área desconhecida", ["ruRU"]="Область неизвестна", ["zhCN"]="区域未知", ["zhTW"]="區域未知", ["koKR"]="지역 미상", ["esMX"]="Zona desconocida"},
    ["Leader"]={["frFR"]="Chef", ["deDE"]="Leiter", ["esES"]="Líder", ["ptBR"]="Líder", ["ruRU"]="Лидер", ["zhCN"]="队长", ["zhTW"]="隊長", ["koKR"]="파티장", ["esMX"]="Líder"},
    ["Replied"]={["frFR"]="Réponse reçue", ["deDE"]="Beantwortet", ["esES"]="Respondido", ["ptBR"]="Respondido", ["ruRU"]="Ответ получен", ["zhCN"]="已回复", ["zhTW"]="已回覆", ["koKR"]="답변됨", ["esMX"]="Respondido"},
    ["Sent"]={["frFR"]="Envoyé", ["deDE"]="Gesendet", ["esES"]="Enviado", ["ptBR"]="Enviado", ["ruRU"]="Отправлено", ["zhCN"]="已发送", ["zhTW"]="已發送", ["koKR"]="전송됨", ["esMX"]="Enviado"},
    ["In grp"]={["frFR"]="En groupe", ["deDE"]="In Gruppe", ["esES"]="En grupo", ["ptBR"]="No grupo", ["ruRU"]="В группе", ["zhCN"]="队伍中", ["zhTW"]="隊伍中", ["koKR"]="파티 중", ["esMX"]="En grupo"},
    ["Group results"]={["frFR"]="Résultats de groupe", ["deDE"]="Gruppenergebnisse", ["esES"]="Resultados de grupos", ["ptBR"]="Resultados de grupos", ["ruRU"]="Результаты поиска", ["zhCN"]="搜索结果", ["zhTW"]="搜尋結果", ["koKR"]="검색 결과", ["esMX"]="Resultados de grupos"},
    ["No matching activities. Try another term or show all level ranges."]={["frFR"]="Aucune activité trouvée. Essayez un autre terme ou affichez tous les niveaux.", ["deDE"]="Keine passenden Aktivitäten. Anderen Begriff versuchen.", ["esES"]="Sin actividades coincidentes. Prueba otro término.", ["ptBR"]="Nenhuma atividade encontrada. Tente outro termo.", ["esMX"]="Sin actividades coincidentes. Prueba otro término."},
    ["Loaded group-aware default template."]={["frFR"]="Modèle de groupe chargé.", ["deDE"]="Gruppenvorlage geladen.", ["esES"]="Plantilla de grupo cargada.", ["ptBR"]="Modelo de grupo carregado.", ["esMX"]="Plantilla de grupo cargada."},
    ["Loaded solo default template."]={["frFR"]="Modèle solo chargé.", ["deDE"]="Solo-Vorlage geladen.", ["esES"]="Plantilla individual cargada.", ["ptBR"]="Modelo solo carregado.", ["esMX"]="Plantilla individual cargada."},
    ["Party Role Manager"]={["frFR"]="Gestion des rôles", ["deDE"]="Rollenverwaltung", ["esES"]="Gestor de roles", ["ptBR"]="Gerenciar funções", ["esMX"]="Gestor de roles"},
    ["Current location:"]={["frFR"]="Position actuelle :", ["deDE"]="Aktueller Standort:", ["esES"]="Ubicación actual:", ["ptBR"]="Localização atual:", ["ruRU"]="Местоположение:", ["zhCN"]="当前位置：", ["zhTW"]="目前位置：", ["koKR"]="현재 위치:", ["esMX"]="Ubicación actual:"},
    ["Party/raid:"]={["frFR"]="Groupe/raid :", ["deDE"]="Gruppe/Raid:", ["esES"]="Grupo/banda:", ["ptBR"]="Grupo/raide:", ["ruRU"]="Группа/рейд:", ["zhCN"]="队伍/团队：", ["zhTW"]="隊伍/團隊：", ["koKR"]="파티/공격대:", ["esMX"]="Grupo/banda:"},
    ["Create Group"]={["frFR"]="Créer un groupe", ["deDE"]="Gruppe erstellen", ["esES"]="Crear grupo", ["ptBR"]="Criar grupo", ["esMX"]="Crear grupo"},
    ["Advanced Filters <<"]={["frFR"]="Filtres avancés <<", ["deDE"]="Erweiterte Filter <<", ["esES"]="Filtros avanzados <<", ["ptBR"]="Filtros avançados <<", ["ruRU"]="Доп. фильтры <<", ["zhCN"]="高级筛选 <<", ["zhTW"]="進階篩選 <<", ["koKR"]="고급 필터 <<", ["esMX"]="Filtros avanzados <<"},
}

local root, lastSource = nil, setmetatable({}, {__mode="k"})
local buttonSources=setmetatable({}, {__mode="k"})
local fontBase=setmetatable({}, {__mode="k"})
local ignored=setmetatable({}, {__mode="k"})
function Locale.Ignore(font) if font then ignored[font]=true end end
local choice = "auto"
local function Readable(v)
    if type(issecretvalue)=="function" and issecretvalue(v) then return nil end
    if type(canaccessvalue)=="function" and not canaccessvalue(v) then return nil end
    return v
end
local function Selected()
    local saved=type(ForeverQuickJoinDB)=="table" and ForeverQuickJoinDB.languageChoice
    if saved=="auto" or LANGS[saved] then return saved end
    return "auto"
end
local function Effective()
    choice=Selected()
    local client=type(GetLocale)=="function" and GetLocale() or "enUS"
    local v=choice=="auto" and client or choice
    return LANGS[v] and v or "enUS"
end
function Locale.Current() return Selected(),Effective() end
function Locale.ShortCode()
    local codes={enUS="EN",frFR="FR",deDE="DE",esES="ES",esMX="ES",ptBR="PT",ruRU="RU",zhCN="ZH",zhTW="ZH",koKR="KO"}
    return codes[Effective()] or "EN"
end

-- Native activity IDs remain authoritative. Only known English display names
-- are localized, and unfamiliar/custom activities retain Blizzard's text.
-- These maps cover common WoW Classic instances and WoW Forever activities;
-- locale variants without a reviewed translation deliberately fall back.
local dungeonNames = {
    ["City of Dalaran"]={frFR="Cité de Dalaran",deDE="Stadt Dalaran",esES="Ciudad de Dalaran",esMX="Ciudad de Dalaran",ptBR="Cidade de Dalaran",ruRU="Город Даларан",zhCN="达拉然城",zhTW="達拉然城",koKR="달라란 도시"},
    ["The Deadmines"]={frFR="Les Mortemines",deDE="Die Todesminen",esES="Las Minas de la Muerte",esMX="Las Minas de la Muerte",ptBR="Minas Mortas",ruRU="Мертвые копи",zhCN="死亡矿井",zhTW="死亡礦坑",koKR="죽음의 폐광"},
    ["Deadmines"]={frFR="Mortemines",deDE="Todesminen",esES="Minas de la Muerte",esMX="Minas de la Muerte",ptBR="Minas Mortas",ruRU="Мертвые копи",zhCN="死亡矿井",zhTW="死亡礦坑",koKR="죽음의 폐광"},
    ["Wailing Caverns"]={frFR="Cavernes des lamentations",deDE="Höhlen des Wehklagens",esES="Cuevas de los Lamentos",esMX="Cuevas de los Lamentos",ptBR="Cavernas Ululantes",ruRU="Пещеры Стенаний",zhCN="哀嚎洞穴",zhTW="哀嚎洞穴",koKR="통곡의 동굴"},
    ["Ragefire Chasm"]={frFR="Gouffre de Ragefeu",deDE="Flammenschlund",esES="Sima Ígnea",esMX="Sima Ígnea",ptBR="Cavernas Ígneas",ruRU="Огненная Пропасть",zhCN="怒焰裂谷",zhTW="怒焰裂谷",koKR="성난불길 협곡"},
    ["Shadowfang Keep"]={frFR="Donjon d'Ombrecroc",deDE="Burg Schattenfang",esES="Castillo de Colmillo Oscuro",esMX="Castillo de Colmillo Oscuro",ptBR="Bastilha da Presa Negra",ruRU="Крепость Темного Клыка",zhCN="影牙城堡",zhTW="影牙城堡",koKR="그림자송곳니 성채"},
    ["Blackfathom Deeps"]={frFR="Profondeurs de Brassenoire",deDE="Tiefschwarze Grotte",esES="Cavernas de Brazanegra",esMX="Cavernas de Brazanegra",ptBR="Profundezas Negras",ruRU="Непроглядная Пучина",zhCN="黑暗深渊",zhTW="黑暗深淵",koKR="검은심연 나락"},
    ["The Stockade"]={frFR="Prison de Hurlevent",deDE="Das Verlies",esES="Las Mazmorras",esMX="Las Mazmorras",ptBR="O Cárcere",ruRU="Тюрьма",zhCN="暴风城监狱",zhTW="暴風城監獄",koKR="스톰윈드 지하감옥"},
    ["Stockades"]={frFR="Prison de Hurlevent",deDE="Verlies von Sturmwind",esES="Mazmorras de Ventormenta",esMX="Mazmorras de Ventormenta",ptBR="Cárcere de Ventobravo",ruRU="Тюрьма Штормграда",zhCN="暴风城监狱",zhTW="暴風城監獄",koKR="스톰윈드 지하감옥"},
    ["Stormwind Stockades"]={frFR="Prison de Hurlevent",deDE="Verlies von Sturmwind",esES="Mazmorras de Ventormenta",esMX="Mazmorras de Ventormenta",ptBR="Cárcere de Ventobravo",ruRU="Тюрьма Штормграда",zhCN="暴风城监狱",zhTW="暴風城監獄",koKR="스톰윈드 지하감옥"},
    ["Gnomeregan"]={frFR="Gnomeregan",deDE="Gnomeregan",esES="Gnomeregan",esMX="Gnomeregan",ptBR="Gnomeregan",ruRU="Гномреган",zhCN="诺莫瑞根",zhTW="諾姆瑞根",koKR="놈리건"},
    ["Razorfen Kraul"]={frFR="Kraal de Tranchebauge",deDE="Kral der Klingenhauer",esES="Horado Rajacieno",esMX="Horado Rajacieno",ptBR="Urzal dos Tuscos",ruRU="Лабиринты Иглошкурых",zhCN="剃刀沼泽",zhTW="剃刀沼澤",koKR="가시덩굴 우리"},
    ["Razorfen Downs"]={frFR="Souilles de Tranchebauge",deDE="Hügel der Klingenhauer",esES="Zahúrda Rajacieno",esMX="Zahúrda Rajacieno",ptBR="Urzal dos Mortos",ruRU="Курганы Иглошкурых",zhCN="剃刀高地",zhTW="剃刀高地",koKR="가시덩굴 구릉"},
    ["Scarlet Monastery"]={frFR="Monastère écarlate",deDE="Scharlachrotes Kloster",esES="Monasterio Escarlata",esMX="Monasterio Escarlata",ptBR="Monastério Escarlate",ruRU="Монастырь Алого ордена",zhCN="血色修道院",zhTW="血色修道院",koKR="붉은십자군 수도원"},
    ["Scarlet Graveyard"]={frFR="Cimetière écarlate",deDE="Scharlachroter Friedhof",esES="Cementerio Escarlata",esMX="Cementerio Escarlata",ptBR="Cemitério Escarlate",ruRU="Кладбище Алого ордена",zhCN="血色墓地",zhTW="血色墓地",koKR="붉은십자군 묘지"},
    ["Scarlet Library"]={frFR="Bibliothèque écarlate",deDE="Scharlachrote Bibliothek",esES="Biblioteca Escarlata",esMX="Biblioteca Escarlata",ptBR="Biblioteca Escarlate",ruRU="Библиотека Алого ордена",zhCN="血色图书馆",zhTW="血色圖書館",koKR="붉은십자군 도서관"},
    ["Scarlet Armory"]={frFR="Armurerie écarlate",deDE="Scharlachrote Waffenkammer",esES="Armería Escarlata",esMX="Armería Escarlata",ptBR="Arsenal Escarlate",ruRU="Оружейная Алого ордена",zhCN="血色军械库",zhTW="血色軍械庫",koKR="붉은십자군 무기고"},
    ["Scarlet Cathedral"]={frFR="Cathédrale écarlate",deDE="Scharlachrote Kathedrale",esES="Catedral Escarlata",esMX="Catedral Escarlata",ptBR="Catedral Escarlate",ruRU="Собор Алого ордена",zhCN="血色教堂",zhTW="血色教堂",koKR="붉은십자군 대성당"},
    ["Uldaman"]={frFR="Uldaman",deDE="Uldaman",esES="Uldaman",esMX="Uldaman",ptBR="Uldaman",ruRU="Ульдаман",zhCN="奥达曼",zhTW="奧達曼",koKR="울다만"},
    ["Zul'Farrak"]={frFR="Zul'Farrak",deDE="Zul'Farrak",esES="Zul'Farrak",esMX="Zul'Farrak",ptBR="Zul'Farrak",ruRU="Зул'Фаррак",zhCN="祖尔法拉克",zhTW="祖爾法拉克",koKR="줄파락"},
    ["Maraudon"]={frFR="Maraudon",deDE="Maraudon",esES="Maraudon",esMX="Maraudon",ptBR="Maraudon",ruRU="Мародон",zhCN="玛拉顿",zhTW="瑪拉頓",koKR="마라우돈"},
    ["Sunken Temple"]={frFR="Temple englouti",deDE="Versunkener Tempel",esES="Templo Sumergido",esMX="Templo Sumergido",ptBR="Templo Submerso",ruRU="Затонувший храм",zhCN="沉没的神庙",zhTW="沉沒的神廟",koKR="가라앉은 사원"},
    ["Temple of Atal'Hakkar"]={frFR="Temple d'Atal'Hakkar",deDE="Tempel von Atal'Hakkar",esES="Templo de Atal'Hakkar",esMX="Templo de Atal'Hakkar",ptBR="Templo de Atal'Hakkar",ruRU="Храм Атал'Хаккара",zhCN="阿塔哈卡神庙",zhTW="阿塔哈卡神廟",koKR="아탈학카르 신전"},
    ["Blackrock Depths"]={frFR="Profondeurs de Rochenoire",deDE="Schwarzfelstiefen",esES="Profundidades de Roca Negra",esMX="Profundidades de Roca Negra",ptBR="Abismo Rocha Negra",ruRU="Глубины Черной горы",zhCN="黑石深渊",zhTW="黑石深淵",koKR="검은바위 나락"},
    ["Blackrock Spire"]={frFR="Pic Rochenoire",deDE="Schwarzfelsspitze",esES="Cumbre de Roca Negra",esMX="Cumbre de Roca Negra",ptBR="Pico da Rocha Negra",ruRU="Пик Черной горы",zhCN="黑石塔",zhTW="黑石塔",koKR="검은바위 첨탑"},
    ["Lower Blackrock Spire"]={frFR="Bas du pic Rochenoire",deDE="Untere Schwarzfelsspitze",esES="Cumbre de Roca Negra inferior",esMX="Cumbre de Roca Negra inferior",ptBR="Pico da Rocha Negra Inferior",ruRU="Нижняя часть пика Черной горы",zhCN="黑石塔下层",zhTW="黑石塔下層",koKR="검은바위 첨탑 하층"},
    ["Upper Blackrock Spire"]={frFR="Haut du pic Rochenoire",deDE="Obere Schwarzfelsspitze",esES="Cumbre de Roca Negra superior",esMX="Cumbre de Roca Negra superior",ptBR="Pico da Rocha Negra Superior",ruRU="Верхняя часть пика Черной горы",zhCN="黑石塔上层",zhTW="黑石塔上層",koKR="검은바위 첨탑 상층"},
    ["Dire Maul"]={frFR="Hache-tripes",deDE="Düsterbruch",esES="La Masacre",esMX="La Masacre",ptBR="Gládio Cruel",ruRU="Забытый Город",zhCN="厄运之槌",zhTW="厄運之槌",koKR="혈투의 전장"},
    ["Stratholme"]={frFR="Stratholme",deDE="Stratholme",esES="Stratholme",esMX="Stratholme",ptBR="Stratholme",ruRU="Стратхольм",zhCN="斯坦索姆",zhTW="斯坦索姆",koKR="스트라솔름"},
    ["Scholomance"]={frFR="Scholomance",deDE="Scholomance",esES="Scholomance",esMX="Scholomance",ptBR="Scolomântia",ruRU="Некроситет",zhCN="通灵学院",zhTW="通靈學院",koKR="스칼로맨스"},
    ["Barrow Deeps"]={frFR="Profondeurs des tertres",deDE="Hügelgruft",esES="Profundidades de los túmulos",esMX="Profundidades de los túmulos",ptBR="Profundezas dos Túmulos"},
    ["The Drowned City"]={frFR="La cité engloutie",deDE="Die versunkene Stadt",esES="La ciudad sumergida",esMX="La ciudad sumergida",ptBR="A Cidade Submersa"},
    ["Alcaz Prison"]={frFR="Prison d'Alcaz",deDE="Alcaz-Gefängnis",esES="Prisión de Alcaz",esMX="Prisión de Alcaz",ptBR="Prisão de Alcaz"},
    ["Ruins of Lordaeron"]={frFR="Ruines de Lordaeron",deDE="Ruinen von Lordaeron",esES="Ruinas de Lordaeron",esMX="Ruinas de Lordaeron",ptBR="Ruínas de Lordaeron"},
    ["Hall of Thanes"]={frFR="Salle des thanes",deDE="Halle der Thane",esES="Sala de los Thanes",esMX="Sala de los Thanes",ptBR="Salão dos Thanes"},
    ["Excavation Site"]={frFR="Site de fouilles",deDE="Ausgrabungsstätte",esES="Yacimiento de excavación",esMX="Yacimiento de excavación",ptBR="Sítio de Escavação"},
    ["Blackmaw Hold"]={frFR="Fort des Gueules-noires",deDE="Schwarzrachen-Feste",esES="Bastión Faucesnegras",esMX="Bastión Faucesnegras",ptBR="Fortaleza Boca Negra"},
    ["Shaper's Terrace"]={frFR="Terrasse du Façonneur",deDE="Terrasse des Formers",esES="Terraza del Moldeador",esMX="Terraza del Moldeador",ptBR="Terraço do Moldador"},
    ["Hyjal Summit"]={frFR="Sommet d'Hyjal",deDE="Hyjalgipfel",esES="Cima Hyjal",esMX="Cima Hyjal",ptBR="Pico Hyjal"},
}

function Locale.DungeonNamesEnabled()
    local stored=type(ForeverQuickJoinDB)=="table" and ForeverQuickJoinDB.translateDungeonNames
    if type(stored)=="boolean" then return stored end
    return Effective()~="enUS"
end
function Locale.SetTranslateDungeonNames(enabled)
    ForeverQuickJoinDB=type(ForeverQuickJoinDB)=="table" and ForeverQuickJoinDB or {}
    ForeverQuickJoinDB.translateDungeonNames=enabled==true
end
function Locale.TranslateDungeonName(name,categoryID)
    if type(issecretvalue)=="function" and issecretvalue(name) then return nil end
    if type(canaccessvalue)=="function" and not canaccessvalue(name) then return nil end
    if type(name)~="string" or not Locale.DungeonNamesEnabled() then return name end
    -- The category guard prevents accidentally translating player-provided
    -- titles or similarly named quest/raid activities.
    if categoryID~=nil and categoryID~=2 then return name end
    local translated=dungeonNames[name]
    return translated and translated[Effective()] or name
end
local templateText = {
    frFR={solo="Niv. {level} {class} {role} cherche un groupe pour {activity}, position : {location}, invitez-moi svp !",group="Niv. {level} {class} {role} cherche un groupe pour {activity}, position : {location}, Groupe : {party}, invitez-nous svp !"},
    deDE={solo="Stufe {level} {class} {role} sucht Gruppe für {activity}, Standort: {location}, bitte einladen!",group="Stufe {level} {class} {role} sucht Gruppe für {activity}, Standort: {location}, Gruppe: {party}, bitte einladen!"},
    esES={solo="Nivel {level} {class} {role} busca grupo para {activity}, ubicación: {location}, ¡invítame!",group="Nivel {level} {class} {role} busca grupo para {activity}, ubicación: {location}, grupo: {party}, ¡invitadnos!"},
    esMX={solo="Nivel {level} {class} {role} busca grupo para {activity}, ubicación: {location}, ¡invítame!",group="Nivel {level} {class} {role} busca grupo para {activity}, ubicación: {location}, grupo: {party}, ¡invítennos!"},
    ptBR={solo="Nível {level} {class} {role} procura grupo para {activity}, localização: {location}, me convide!",group="Nível {level} {class} {role} procura grupo para {activity}, localização: {location}, grupo: {party}, nos convide!"},
    ruRU={solo="Ур. {level} {class} {role} ищет группу для {activity}, местоположение: {location}, пригласите!",group="Ур. {level} {class} {role} ищет группу для {activity}, местоположение: {location}, группа: {party}, пригласите!"},
    zhCN={solo="{level}级 {class} {role} 寻找{activity}队伍，当前位置：{location}，请邀请！",group="{level}级 {class} {role} 寻找{activity}队伍，当前位置：{location}，队伍：{party}，请邀请！"},
    zhTW={solo="{level}級 {class} {role} 尋找{activity}隊伍，目前位置：{location}，請邀請！",group="{level}級 {class} {role} 尋找{activity}隊伍，目前位置：{location}，隊伍：{party}，請邀請！"},
    koKR={solo="{level}레벨 {class} {role} {activity} 파티 구합니다. 현재 위치: {location}, 초대 부탁드립니다!",group="{level}레벨 {class} {role} {activity} 파티 구합니다. 현재 위치: {location}, 파티: {party}, 초대 부탁드립니다!"},
}
function Locale.DefaultWhisperTemplate(grouped,english)
    local options=templateText[Effective()]
    if not options then return english end
    return options[grouped and "group" or "solo"] or english
end

-- Chat LFG one-click reply is separate from the editable Group Listings
-- template. It follows the language but never modifies saved player text.
function Locale.ChatLFGReply(activity)
    local formats={
        frFR="J'ai vu votre annonce RdG pour %s. Cherchez-vous toujours un groupe ?",
        deDE="Ich habe deine Gruppensuche für %s gesehen. Suchst du noch eine Gruppe?",
        esES="Vi tu anuncio para %s. ¿Sigues buscando grupo?",
        esMX="Vi tu anuncio para %s. ¿Sigues buscando grupo?",
        ptBR="Vi seu anúncio para %s. Ainda está procurando grupo?",
        ruRU="Видел объявление о поиске группы для %s. Вы ещё ищете группу?",
        zhCN="看到你寻找%s队伍的消息。还在找队伍吗？",
        zhTW="看到你尋找%s隊伍的訊息。還在找隊伍嗎？",
        koKR="%s 파티를 구한다는 글을 봤습니다. 아직 파티를 찾으시나요?",
    }
    if type(activity)~="string" then activity="" end
    local template=formats[Effective()]
    return template and template:format(activity)
        or ("I saw your LFG post for "..activity..". Are you still looking for a group?")
end

-- UI-generated English status strings are translated by their stable
-- prefixes/patterns. Embedded names, activities and player messages are data.
local function W(key,lang)
    local item=dict[key]
    return item and item[lang] or key
end
local function DynamicTranslate(source,lang)
    local role=source:match("^Solo — role: (.+)$")
    if role then
        local prefixes={frFR="Solo — rôle : ",deDE="Solo — Rolle: ",esES="Solo — rol: ",esMX="Solo — rol: ",ptBR="Solo — função: ",ruRU="Один — роль: ",zhCN="单人 — 职责：",zhTW="單人 — 職責：",koKR="솔로 — 역할: "}
        return (prefixes[lang] or "Solo — role: ")..W(role,lang)
    end
    local party,mark=source:match("^Party detected %((%d+)%) ?(!?)$")
    if party then return W("Party detected",lang).." ("..party..")"..(mark=="!" and " !" or "") end
    local need=source:match("^(%d+) roles? need review$")
    if need then
        local suffix={frFR=" rôle(s) à vérifier",deDE=" Rolle(n) prüfen",esES=" rol(es) por revisar",esMX=" rol(es) por revisar",ptBR=" função(ões) para revisar",ruRU=" ролей проверить",zhCN=" 个职责待检查",zhTW=" 個職責待檢查",koKR="개 역할 확인 필요"}
        return need..(suffix[lang] or " roles need review")
    end
    local unknown=source:match("^Unassigned: (%d+)$")
    if unknown then return W("Unassigned",lang)..": "..unknown end
    local page,pages,groups=source:match("^Page (%d+) / (%d+)  %((%d+) groups%)$")
    if page then
        local word={frFR="groupes",deDE="Gruppen",esES="grupos",esMX="grupos",ptBR="grupos",ruRU="групп",zhCN="队伍",zhTW="隊伍",koKR="파티"}
        local label={frFR="Page",deDE="Seite",esES="Página",esMX="Página",ptBR="Página",ruRU="Страница",zhCN="页",zhTW="頁",koKR="페이지"}
        return (label[lang] or "Page").." "..page.." / "..pages.."  ("..groups.." "..(word[lang] or "groups")..")"
    end
    local p,of=source:match("^Page (%d+) / (%d+)$")
    if p then
        local label={frFR="Page",deDE="Seite",esES="Página",esMX="Página",ptBR="Página",ruRU="Страница",zhCN="页",zhTW="頁",koKR="페이지"}
        return (label[lang] or "Page").." "..p.." / "..of
    end
    local seen,total=source:match("^Showing (%d+) of (%d+) cached groups%. Search updates listings; filters are local%.$")
    if seen then
        local formats={
            frFR="%s groupes affichés sur %s en cache. Recherche : annonces actualisées ; filtres locaux.",
            deDE="%s von %s gespeicherten Gruppen. Suche aktualisiert, Filter sind lokal.",
            esES="%s de %s grupos guardados. Buscar actualiza; filtros locales.",
            esMX="%s de %s grupos guardados. Buscar actualiza; filtros locales.",
            ptBR="%s de %s grupos em cache. A busca atualiza; filtros locais.",
            ruRU="Показано %s из %s групп. Поиск обновляет; фильтры локальные.",
            zhCN="显示 %s / %s 个缓存队伍。搜索刷新列表；筛选仅本地。",
            zhTW="顯示 %s / %s 個快取隊伍。搜尋更新列表；篩選僅本機。",
            koKR="저장된 %s / %s 파티. 검색으로 갱신, 필터는 로컬 적용."
        }
        if formats[lang] then return formats[lang]:format(seen,total) end
    end
    local place,group=source:match("^Current location: (.-)   |   (.+)$")
    if place then
        local partySize=group:match("^Party/raid: (%d+) total %(including you%)$")
        local translated=group
        if partySize then
            local names={frFR=" membres (vous compris)",deDE=" gesamt (mit dir)",esES=" en total (incluyéndote)",esMX=" en total (incluyéndote)",ptBR=" no total (incluindo você)",ruRU=" всего (включая вас)",zhCN=" 人（含你）",zhTW=" 人（含你）",koKR="명 (본인 포함)"}
            translated=W("Party/raid:",lang).." "..partySize..(names[lang] or " total (including you)")
        elseif group=="Solo" then translated=W("Solo",lang) end
        return W("Current location:",lang).." "..place.."   |   "..translated
    end
    local members=source:match("^GROUP MEMBERS %((%d+)%)  ·  Right%-click: /who or whisper$")
    if members then
        local names={frFR="MEMBRES DU GROUPE",deDE="GRUPPENMITGLIEDER",esES="MIEMBROS",esMX="MIEMBROS",ptBR="MEMBROS",ruRU="УЧАСТНИКИ",zhCN="队伍成员",zhTW="隊伍成員",koKR="파티원"}
        local actions={frFR="Clic droit : /who ou murmure",deDE="Rechtsklick: /who oder Flüstern",esES="Clic derecho: /who o susurro",esMX="Clic derecho: /who o susurro",ptBR="Botão direito: /who ou sussurro",ruRU="ПКМ: /who или сообщение",zhCN="右键：/who 或密语",zhTW="右鍵：/who 或密語",koKR="우클릭: /who 또는 귓속말"}
        return (names[lang] or "GROUP MEMBERS").." ("..members..")  ·  "..(actions[lang] or "Right-click: /who or whisper")
    end
    local activity=source:match("^Activities: (.+)$")
    if activity then return W("Activities:",lang).." "..activity end
    local n=source:match("^Party (%d+); (%d+) to review")
    if n then
        local labels={frFR="Groupe : ",deDE="Gruppe: ",esES="Grupo: ",esMX="Grupo: ",ptBR="Grupo: ",ruRU="Группа: ",zhCN="队伍：",zhTW="隊伍：",koKR="파티: "}
        local count=source:match("^Party %d+; (%d+) to review") or "0"
        local reviewLabels={frFR=" à vérifier. Les corrections ne modifient pas les rôles Blizzard.",deDE=" prüfen. Korrekturen ändern keine Blizzard-Rollen.",esES=" por revisar. Los cambios no modifican los roles Blizzard.",esMX=" por revisar. Los cambios no modifican los roles Blizzard.",ptBR=" para revisar. As mudanças não alteram os papéis Blizzard.",ruRU=" проверить. Исправления не меняют роли Blizzard.",zhCN=" 待检查；不会修改暴雪职责。",zhTW=" 待檢查；不會修改暴雪職責。",koKR=" 확인 필요. 블리자드 역할은 변경되지 않습니다."}
        return (labels[lang] or "Party ")..n.."; "..count..(reviewLabels[lang] or " to review")
    end
    local namedRole=source:match("^Role: ([%a]+)$")
    if namedRole then
        local prefix={frFR="Rôle : ",deDE="Rolle: ",esES="Rol: ",esMX="Rol: ",ptBR="Função: ",ruRU="Роль: ",zhCN="职责：",zhTW="職責：",koKR="역할: "}
        return (prefix[lang] or "Role: ")..W(namedRole,lang)
    end
    return source
end
function Locale.Translate(source)
    source=Readable(source)
    if type(source)~="string" then return source end
    local lang=Effective()
    if lang=="enUS" then return source end
    local exact=dict[source]
    if exact then return exact[lang] or source end
    return DynamicTranslate(source,lang)
end
function Locale.SourceFor(font)
    if not font then return nil end
    local data=lastSource[font]
    if data and type(font.GetText)=="function" then
        local ok,value=pcall(font.GetText,font)
        if ok and value==data.display then return data.source end
    end
    -- Styled WoW buttons have several text regions, not all of which
    -- are visible or owned by the same current font object.
    local parent=type(font.GetParent)=="function" and font:GetParent()
    data=parent and buttonSources[parent]
    if data and type(parent.GetText)=="function" and parent:GetText()==data.display then
        return data.source
    end
    return nil
end
local function TranslateFont(font)
    if not font or ignored[font] or type(font.GetText)~="function"
        or type(font.SetText)~="function" then return end
    local ok,text=pcall(font.GetText,font)
    if not ok then return end
    text=Readable(text)
    if type(text)~="string" or text=="" then return end
    local last=lastSource[font]
    local english=last and last.display==text and last.source or text
    local translated=Locale.Translate(english)
    if translated~=text then pcall(font.SetText,font,translated) end
    if translated~=english or last then lastSource[font]={source=english,display=translated} end
end
local function FitButton(button)
    if type(button.GetFontString)~="function" or type(button.GetWidth)~="function" then return end
    local font=button:GetFontString()
    if not font then return end
    local width=button:GetWidth()
    if type(width)~="number" or width<30 then return end
    -- Keep text confined to its own button, regardless of selected language.
    if type(font.SetWordWrap)=="function" then font:SetWordWrap(false) end
    if type(font.SetJustifyH)=="function" then font:SetJustifyH("CENTER") end
    if type(font.SetMaxLines)=="function" then font:SetMaxLines(1) end
    local limit=math.max(22,width-12)
    if type(font.GetFont)~="function" or type(font.SetFont)~="function" then return end
    local family,size,flags=font:GetFont()
    if type(family)~="string" or type(size)~="number" then return end
    local base=fontBase[font]
    local caption=type(button.GetText)=="function" and button:GetText()
    if not base or base.family~=family then
        base={family=family,size=size,flags=flags}
        fontBase[font]=base
    end
    -- Unchanged shrunk text must not alternate between sizes every update.
    if base.caption==caption and base.width==width and size==base.fitted then return end
    -- If the Theme system reset the font, treat its new size as the baseline.
    if size>base.size then base.size=size; base.flags=flags end
    if size~=base.size then pcall(font.SetFont,font,family,base.size,base.flags) end
    local measured=type(font.GetUnboundedStringWidth)=="function"
        and font:GetUnboundedStringWidth() or nil
    local desired=base.size
    if type(measured)=="number" and measured>limit and measured>0 then
        desired=math.max(9,math.floor(base.size*limit/measured))
    end
    if desired~=base.size then pcall(font.SetFont,font,family,desired,base.flags) end
    base.caption=caption; base.width=width; base.fitted=desired
end
local function TranslateButton(button)
    if type(button.GetText)~="function" or type(button.SetText)~="function" then return end
    local ok,value=pcall(button.GetText,button)
    if not ok or type(Readable(value))~="string" or value=="" then return end
    local last=buttonSources[button]
    local english=last and last.display==value and last.source or value
    local localized=Locale.Translate(english)
    if localized~=value then pcall(button.SetText,button,localized) end
    if localized~=english or last then
        buttonSources[button]={source=english,display=localized}
    end
    FitButton(button)
end
function Locale.Refresh()
    if not root then return end
    local visited,visitedCount={},0
    local function Scan(frame)
        if not frame or visited[frame] or visitedCount>1800 then return end
        visited[frame]=true;visitedCount=visitedCount+1
        local kind=type(frame.GetObjectType)=="function" and frame:GetObjectType()
        if kind=="Button" then TranslateButton(frame)
        elseif kind=="FontString" then
            local parent=type(frame.GetParent)=="function" and frame:GetParent()
            local parentKind=parent and type(parent.GetObjectType)=="function" and parent:GetObjectType()
            if parentKind~="Button" then TranslateFont(frame) end
        end
        if type(frame.GetRegions)=="function" then
            local regions={frame:GetRegions()}
            for _,r in ipairs(regions) do
                if kind~="Button" and type(r.GetObjectType)=="function"
                    and r:GetObjectType()=="FontString" then TranslateFont(r) end
            end
        end
        if type(frame.GetChildren)=="function" then
            local children={frame:GetChildren()}
            for _,child in ipairs(children) do Scan(child) end
        end
    end
    Scan(root)
end
function Locale.Select(lang)
    if lang~="auto" and not LANGS[lang] then return end
    ForeverQuickJoinDB=type(ForeverQuickJoinDB)=="table" and ForeverQuickJoinDB or {}
    ForeverQuickJoinDB.languageChoice=lang
    choice=lang
    Locale.Refresh()
end
function Locale.Attach(window)
    if root then return end
    root=window
    local timer=0
    if type(window.HookScript)=="function" then
        window:HookScript("OnUpdate",function(_,elapsed)
            timer=timer+(type(elapsed)=="number" and elapsed or 0)
            if timer>=0.65 then timer=0;Locale.Refresh() end
        end)
    end
    Locale.Refresh()
end
