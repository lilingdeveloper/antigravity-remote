# -*- coding: utf-8 -*-
"""AGY Remote 12 语言 App Store Connect 元数据 (AppInfo + Version Localization + Review Detail)"""

import json
import os

PRIVACY_URL = "https://lilingdeveloper.github.io/antigravity-remote/privacy.html"
SUPPORT_URL = "https://lilingdeveloper.github.io/antigravity-remote/support.html"
MARKETING_URL = "https://github.com/lilingdeveloper/antigravity-remote"
COPYRIGHT = "2026 Antigravity Remote Contributors"


def _load_asc_config():
    cfg_dir = os.path.expanduser(os.environ.get("ASC_CONFIG_DIR", "~/.appstoreconnect"))
    cfg_path = os.path.join(cfg_dir, "config.json")
    if os.path.exists(cfg_path):
        try:
            with open(cfg_path, encoding="utf-8") as f:
                return json.load(f)
        except Exception:
            pass
    return {}


_CFG = _load_asc_config()

REVIEW_DETAIL = {
    "contactFirstName": os.environ.get("ASC_CONTACT_FIRST_NAME") or _CFG.get("contact_first_name") or "Developer",
    "contactLastName": os.environ.get("ASC_CONTACT_LAST_NAME") or _CFG.get("contact_last_name") or "Support",
    "contactPhone": os.environ.get("ASC_CONTACT_PHONE") or _CFG.get("contact_phone") or "",
    "contactEmail": os.environ.get("ASC_CONTACT_EMAIL") or _CFG.get("contact_email") or "",
    "demoAccountName": None,
    "demoAccountPassword": None,
    "demoAccountRequired": False,
    "notes": (
        "APP REVIEW INFORMATION — AGY Remote 1.0.0 (Guideline 2.1 App Completeness & Demo Testing)\n\n"
        "Dear App Review Team,\n\n"
        "AGY Remote is a mobile remote companion for developers to monitor and control their own Mac AI coding workspace over LAN or Tailscale.\n"
        "Because reviewers do not need a live Mac running the companion bridge service during review, we have built a full interactive offline Demo Mode directly into the app.\n\n"
        "HOW TO TEST ALL FEATURES IN 1 TAP (NO MAC OR ACCOUNT REQUIRED):\n"
        "1. Launch the app on iPhone or iPad.\n"
        "2. Tap the prominent button \"Try Interactive Demo Mode (No Mac Required)\" / \"体验交互演示模式（无需连接 Mac）\" on the welcome screen.\n"
        "   (Alternatively, tap the top-right Settings gear icon -> Advanced Connection Settings -> enter Host \"0.0.0.0\" or \"demo\" -> Save & Reconnect).\n"
        "3. Once in Demo Mode, you can immediately test all core features:\n"
        "   • Remote Chat & Streaming AI Thinking: Expand/collapse AI thinking cards, inspect tool call pills (read_file / edit_file / run_command), copy syntax-highlighted code blocks, and send any message in the input box to receive simulated streaming AI responses.\n"
        "   • Remote Command & Plan Approvals: Tap \"Trigger Approval Demo\" on the top demo banner (or send a message containing \"test\") to bring up the interactive terminal command approval card, and tap Approve or Reject.\n"
        "   • Multi-Project Sidebar: Swipe right from the left edge (or tap the top-left sidebar button) to switch between demo projects and conversations, rename or archive conversations.\n"
        "   • Inline Plan Documents & Code Diffs: Expand the collapsible \"Plan & Code Changes\" (方案规划与代码修改) category card inside the conversation and tap any file or Markdown plan to inspect full diffs and artifacts in a modal card.\n"
        "   • Multi-Model Quota, Permission Modes & 12-Language Switcher: Tap the 5h/1w quota pills in the top header bar or the model selector in the bottom composer bar to switch AI models and permission modes (Review / Auto / Turbo), or tap the top-right Settings gear button to switch between 12 languages.\n\n"
        "PRIVACY & NO EXTERNAL ACCOUNTS:\n"
        "No login or account registration is required to use the app or Demo Mode. All connections in production are strictly peer-to-peer between the user's iOS device and their own Mac."
    ),
}

METADATA = {
    "zh-Hans": {
        "name": "AGY Remote",
        "subtitle": "Antigravity 移动远程辅助工具",
        "promotionalText": "专为桌面端 Antigravity 开发的移动端远程控制辅助工具（针对部分地区账号未提供移动端远程控制功能）。支持在手机上查看对话、审批命令及查阅代码变更。",
        "keywords": "antigravity,remote control,远程控制,AI编程,tailscale,代码对比,开发者工具,终端审批,agent,mac远程",
        "whatsNew": "• 初始版本：专为桌面端 Antigravity 提供局域网与 Tailscale 移动端远程连接\n• 同步显示 Antigravity 对话内容、思考过程、工具调用步骤与模型额度状态\n• 支持远程处理终端命令审批、方案确认与问题选择\n• 内置离线演示模式与 12 种语言界面",
        "description": (
            "【使用前说明】\n"
            "本软件是专门针对桌面端 Antigravity 开发的独立第三方辅助工具。由于 Antigravity 的一些地区的账号没有提供移动端远程控制（Remote Control）功能，本应用旨在为这类用户提供相应的远程连接支持，方便在离开电脑时通过 iPhone 或 iPad 查看和控制 Mac 上的 Antigravity 会话。如果您未在 Mac 上使用 Antigravity，下载本软件将没有实际用途。\n\n"
            "主要功能：\n\n"
            "1. Antigravity 会话同步与状态查看\n"
            "• 同步展示 Mac 端 Antigravity 当前项目与历史对话列表、AI 思考过程、工具调用记录及代码块。\n"
            "• 顶部状态栏显示当前连接通道（局域网或 Tailscale）以及所选模型的 5 小时与 1 周剩余额度。\n"
            "• 支持在任务运行期间发送新消息进入待发队列，或随时停止当前正在执行的任务。\n\n"
            "2. 远程命令审批与模式切换\n"
            "• 当电脑端 Antigravity 任务需要人工确认终端命令（批准 / 拒绝）、确认实施方案或回答多选题时，可在手机端直接操作。\n"
            "• 底部输入框支持同步和切换电脑端的权限模式（审核 / 自动 / Turbo）与 AI 模型。\n\n"
            "3. 代码变更与方案文档查阅\n"
            "• 会话中的方案规划文档与代码文件修改记录默认折叠归类，点击后可以卡片窗口形式查看完整的 Markdown 文档或代码差异（Diff）。\n\n"
            "4. 连接方式与数据隐私\n"
            "• 本应用需配合用户在自己 Mac 上运行的开源守护进程（读取本机 Antigravity 接口）使用，支持局域网直连和 Tailscale 虚拟局域网连接。\n"
            "• 应用为独立第三方开源项目，不包含广告与统计追踪，无需注册账号，所有数据仅在用户的 iOS 设备与个人 Mac 之间直接传输。\n"
            "• 内置离线演示模式，供连接前快速预览界面布局。"
        ),
    },
    "zh-Hant": {
        "name": "AGY Remote",
        "subtitle": "Antigravity 行動遠端輔助工具",
        "promotionalText": "專為桌面端 Antigravity 開發的行動端遠端控制輔助工具（針對部分地區帳號未提供行動端遠端控制功能）。支援在手機上查看對話、審批指令及查閱程式碼變更。",
        "keywords": "antigravity,remote control,遠端控制,AI程式,tailscale,程式碼對比,開發者工具,終端審批,agent,mac遠端",
        "whatsNew": "• 初始版本：專為桌面端 Antigravity 提供區域網路與 Tailscale 行動端遠端連線\n• 同步顯示 Antigravity 對話內容、思考過程、工具呼叫步驟與模型額度狀態\n• 支援遠端處理終端機指令審批、方案確認與問題選擇\n• 內建離線示範模式與 12 種語言介面",
        "description": (
            "【使用前說明】\n"
            "本軟體是專門針對桌面端 Antigravity 開發的獨立第三方輔助工具。由於 Antigravity 的一些地區的帳號沒有提供行動端遠端控制（Remote Control）功能，本應用旨在為這類使用者提供相應的遠端連線支援，方便在離開電腦時透過 iPhone 或 iPad 查看和控制 Mac 上的 Antigravity 工作階段。如果您未在 Mac 上使用 Antigravity，下載本軟體將沒有實際用途。\n\n"
            "主要功能：\n\n"
            "1. Antigravity 工作階段同步與狀態查看\n"
            "• 同步展示 Mac 端 Antigravity 目前專案與歷史對話列表、AI 思考過程、工具呼叫記錄及程式碼區塊。\n"
            "• 頂部狀態列顯示目前連線通道（區域網路或 Tailscale）以及所選模型的 5 小時與 1 週剩餘額度。\n"
            "• 支援在任務執行期間發送新訊息進入待發佇列，或隨時停止目前正在執行的任務。\n\n"
            "2. 遠端指令審批與模式切換\n"
            "• 當電腦端 Antigravity 任務需要人工確認終端機指令（批准 / 拒絕）、確認實施方案或回答選擇題時，可在手機端直接操作。\n"
            "• 底部輸入框支援同步和切換電腦端的權限模式（審核 / 自動 / Turbo）與 AI 模型。\n\n"
            "3. 程式碼變更與方案文件查閱\n"
            "• 對話中的方案規劃文件與程式碼檔案修改記錄預設折疊歸類，點擊後可以卡片視窗形式查看完整的 Markdown 文件或程式碼差異（Diff）。\n\n"
            "4. 連線方式與資料隱私\n"
            "• 本應用需配合使用者在自己 Mac 上執行的開源橋接服務使用，支援區域網路直連和 Tailscale 虛擬區域網路連線。\n"
            "• 應用為獨立第三方開源專案，不包含廣告與第三方統計，無需註冊帳號，所有資料僅在使用者的 iOS 裝置與個人 Mac 之間直接傳輸。\n"
            "• 內建離線示範模式，供連線前預覽介面與互動流程。"
        ),
    },
    "en-US": {
        "name": "AGY Remote",
        "subtitle": "Remote Client for Antigravity",
        "promotionalText": "An independent mobile companion tool for desktop Antigravity, built for accounts in regions where mobile remote control is unavailable. Requires Antigravity on Mac.",
        "keywords": "antigravity,remote control,ai coding,tailscale,code diff,developer tools,agent,ide remote,mac",
        "whatsNew": "• Initial release: Connect to desktop Antigravity on your Mac via LAN or Tailscale\n• View Antigravity conversations, thinking steps, tool calls, and model quotas\n• Remotely approve or reject terminal commands, implementation plans, and prompts\n• Built-in offline Demo Mode and 12-language interface support",
        "description": (
            "[Important Note Before Downloading]\n"
            "AGY Remote is an independent, third-party companion tool built specifically for the desktop Antigravity IDE. Because Antigravity accounts in some regions do not provide a mobile Remote Control feature, this app was created to let affected users view and control their Mac Antigravity sessions from an iPhone or iPad. If you do not use Antigravity on a Mac, this app will not be useful to you.\n\n"
            "Key Functions:\n\n"
            "1. Antigravity Session Sync & Status\n"
            "• Displays active and historical Antigravity conversations grouped by project, along with AI thinking steps, tool calls, and code blocks.\n"
            "• Shows the current connection route (LAN or Tailscale) as well as 5-hour and 1-week model quota status in the top bar.\n"
            "• Supports queueing follow-up messages while a task is running, or stopping an active run at any time.\n\n"
            "2. Remote Approvals & Mode Switching\n"
            "• Handle pending Antigravity terminal command approvals (Approve / Reject), implementation plan confirmations, and multiple-choice questions remotely.\n"
            "• Synchronize and switch permission modes (Review / Auto / Turbo) and AI models directly from the bottom input bar.\n\n"
            "3. Code Diffs & Plan Documents\n"
            "• Implementation plans and modified source files are grouped into a collapsible inline summary card within the chat, and can be opened in a modal view to inspect full Markdown documents or code diffs.\n\n"
            "4. Connectivity & Privacy\n"
            "• Works with an open-source companion daemon running on your own Mac over local network (LAN) or Tailscale.\n"
            "• Unofficial third-party tool: requires no user account, contains no ads or analytics, and transfers data strictly peer-to-peer between your iOS device and your Mac.\n"
            "• Includes an offline Demo Mode for previewing the interface before connecting."
        ),
    },
    "ja": {
        "name": "AGY Remote",
        "subtitle": "Antigravity用リモート補助ツール",
        "promotionalText": "一部の地域のアカウントでモバイル遠隔操作が提供されていないデスクトップ版Antigravity向けの補助クライアントです（Mac上のAntigravityが必要）。",
        "keywords": "antigravity,リモート操作,AI開発,tailscale,コード差分,開発ツール,エージェント,ターミナル承認,mac連携",
        "whatsNew": "• 初回リリース：Mac上のAntigravityへLANおよびTailscale経由でリモート接続\n• Antigravityの会話履歴、思考ステップ、ツール呼び出し、モデル利用枠の表示\n• ターミナルコマンドの承認・拒否および計画確認のリモート操作\n• オフラインデモモードと12言語のUI表示に対応",
        "description": (
            "【ダウンロード前のご注意】\n"
            "本アプリは、デスクトップ版「Antigravity」専用に開発された独立したサードパーティ製の補助クライアントです。Antigravityでは一部の地域のアカウントにおいてモバイル向けのリモート操作（Remote Control）機能が提供されていないため、席を離れている際にもiPhoneやiPadからMac上のAntigravityセッションを確認・操作できるように作られました。MacでAntigravityを使用していない場合、本アプリはご利用いただけません。\n\n"
            "主な機能：\n\n"
            "1. Antigravityセッションの同期とステータス確認\n"
            "• Mac上のAntigravityのプロジェクト別会話一覧、思考プロセス、ツール呼び出し履歴、コードブロックを表示します。\n"
            "• 上部バーに接続経路（LANまたはTailscale）と選択中モデルの5時間・1週間の残り利用枠を表示します。\n\n"
            "2. リモート承認とモード切り替え\n"
            "• ターミナルコマンドの実行確認（承認・拒否）、実装計画の確認、選択式の質問への回答をモバイル端末から行えます。\n"
            "• 下部バーから権限モード（Review / Auto / Turbo）やAIモデルの切り替え、実行中タスクの停止が可能です。\n\n"
            "3. コード差分（Diff）と計画ドキュメントの閲覧\n"
            "• 計画ドキュメントと変更されたソースファイルは会話内に折りたたんでまとめられ、タップして差分やMarkdown全文を確認できます。\n\n"
            "4. 接続方式とプライバシー\n"
            "• ご自身のMacで動作するオープンソースのブリッジサービスとLANまたはTailscale経由で直接通信します。アカウント登録やデータ収集はなく、オフラインで画面を確認できるデモモードも備えています。"
        ),
    },
    "ko": {
        "name": "AGY Remote",
        "subtitle": "Antigravity용 모바일 원격 보조 도구",
        "promotionalText": "일부 지역 계정에서 모바일 원격 제어 기능이 제공되지 않는 데스크톱 Antigravity를 위해 개발된 보조 클라이언트입니다 (Mac용 Antigravity 필요).",
        "keywords": "antigravity,원격제어,AI코딩,tailscale,코드비교,개발자도구,에이전트,터미널승인,맥원격",
        "whatsNew": "• 첫 출시: LAN 및 Tailscale을 통한 Mac의 Antigravity 원격 연결 지원\n• Antigravity 대화 기록, 사고 과정, 도구 호출 단계 및 모델 할당량 표시\n• 터미널 명령 승인/거절 및 실행 계획 원격 확인\n• 오프라인 데모 모드 및 12개 언어 인터페이스 지원",
        "description": (
            "[다운로드 전 안내]\n"
            "본 앱은 데스크톱용 Antigravity를 위해 개발된 독립 서드파티 보조 도구입니다. Antigravity의 일부 지역 계정에서는 모바일 원격 제어(Remote Control) 기능이 제공되지 않아, 자리를 비웠을 때 iPhone이나 iPad에서 Mac의 Antigravity 세션을 확인하고 제어할 수 있도록 제작되었습니다. Mac에서 Antigravity를 사용하지 않는 분께는 본 앱이 쓸모가 없습니다.\n\n"
            "주요 기능:\n\n"
            "1. Antigravity 대화 동기화 및 상태 확인\n"
            "• 프로젝트별 Antigravity 대화 목록, AI 사고 과정, 도구 호출 기록 및 코드 블록을 동기화하여 표시합니다.\n"
            "• 상단 바에 현재 연결 경로(LAN 또는 Tailscale)와 선택된 모델의 5시간 및 1주일 잔여 할당량을 표시합니다.\n\n"
            "2. 원격 승인 및 모드 전환\n"
            "• 터미널 명령 실행 확인(승인/거절), 구현 계획 확인 및 객관식 질문 응답을 모바일에서 처리할 수 있습니다.\n"
            "• 하단 입력창에서 권한 모드(Review / Auto / Turbo)와 AI 모델을 전환하거나 실행 중인 작업을 중지할 수 있습니다.\n\n"
            "3. 코드 변경(Diff) 및 계획 문서 열람\n"
            "• 계획 문서와 수정된 코드 파일은 대화창 내에 접이식 카드로 정리되며, 탭하여 전체 마크다운 문서나 코드 변경 내역을 확인할 수 있습니다.\n\n"
            "4. 연결 방식 및 개인정보 보호\n"
            "• 사용자의 Mac에서 실행되는 오픈소스 브리지 서비스와 LAN 또는 Tailscale로 직접 통신합니다. 광고나 데이터 수집이 없으며, 오프라인 데모 모드를 포함하고 있습니다."
        ),
    },
    "fr-FR": {
        "name": "AGY Remote",
        "subtitle": "Client distant Antigravity",
        "promotionalText": "Outil compagnon pour Antigravity sur Mac, destiné aux comptes de certaines régions sans contrôle mobile à distance (Antigravity sur Mac requis).",
        "keywords": "antigravity,contrôle distant,codage ia,tailscale,diff code,outils dev,agent,terminal,mac",
        "whatsNew": "• Version initiale : Connexion à Antigravity sur Mac via LAN et Tailscale\n• Affichage des conversations Antigravity, des étapes de réflexion et des quotas\n• Approbation à distance des commandes terminal et des plans d'implémentation\n• Mode Démo hors-ligne et interface en 12 langues",
        "description": (
            "[Note importante avant le téléchargement]\n"
            "AGY Remote est un client compagnon tiers indépendant conçu exclusivement pour le logiciel Antigravity sur Mac. Les comptes Antigravity de certaines régions ne disposant pas de la fonction de contrôle à distance mobile (Remote Control), cette application permet de suivre et de contrôler vos sessions Antigravity depuis un iPhone ou un iPad. Si vous n'utilisez pas Antigravity sur Mac, cette application ne vous sera d'aucune utilité.\n\n"
            "• Suivi des sessions Antigravity : Affiche les conversations par projet, les étapes de réflexion, les appels d'outils ainsi que les quotas (5 heures et 1 semaine) du modèle sélectionné.\n"
            "• Approbations et modes : Permet d'accepter ou de refuser les commandes terminal, de valider les plans, de répondre aux questions et de changer de mode de permission (Review / Auto / Turbo) ou de modèle.\n"
            "• Diffs et documents : Regroupe les plans Markdown et les modifications de fichiers dans une carte repliable au sein de la conversation.\n"
            "• Connexion et confidentialité : Fonctionne en pair-à-pair via LAN ou Tailscale avec le service open-source installé sur votre Mac. Aucune collecte de données, aucune publicité, et un mode démo hors-ligne est inclus."
        ),
    },
    "de-DE": {
        "name": "AGY Remote",
        "subtitle": "Remote-Tool für Antigravity",
        "promotionalText": "Begleit-Tool für Antigravity auf dem Mac, gedacht für Konten in Regionen ohne mobile Fernsteuerungsfunktion (erfordert Antigravity auf dem Mac).",
        "keywords": "antigravity,fernsteuerung,ki coding,tailscale,code diff,entwickler,agent,terminal,mac",
        "whatsNew": "• Erstveröffentlichung: Verbindung zu Antigravity auf dem Mac über LAN und Tailscale\n• Anzeige von Antigravity-Gesprächen, Denkschritten, Tools und Modell-Kontingenten\n• Fernfreigabe von Terminal-Befehlen und Implementierungsplänen\n• Offline-Demomodus und Unterstützung für 12 Sprachen",
        "description": (
            "[Wichtiger Hinweis vor dem Download]\n"
            "AGY Remote ist ein unabhängiger Drittanbieter-Client, der ausschließlich für die Desktop-Anwendung Antigravity entwickelt wurde. Da Antigravity-Konten in einigen Regionen keine mobile Fernsteuerung (Remote Control) bieten, dient dieses Tool dazu, Antigravity-Sitzungen auf dem Mac vom iPhone oder iPad aus einzusehen und zu steuern. Wenn Sie Antigravity nicht auf einem Mac nutzen, hat diese App für Sie keinen Nutzen.\n\n"
            "• Antigravity-Sitzungsanzeige: Synchronisiert Gespräche nach Projekt, Denkschritte, Tool-Aufrufe sowie die 5-Stunden- und 1-Wochen-Kontingente des gewählten Modells.\n"
            "• Fernfreigaben und Moduswechsel: Bestätigen oder ablehnen von Terminal-Befehlen und Plänen, wechseln des Berechtigungsmodus (Review / Auto / Turbo) und Stoppen laufender Aufgaben.\n"
            "• Code-Diffs und Plandokumente: Fasst Plandokumente und Dateiänderungen kompakt im Chat zusammen.\n"
            "• Verbindung und Datenschutz: Direkte Peer-to-Peer-Verbindung über LAN oder Tailscale zum Open-Source-Dienst auf Ihrem Mac. Keine Datenerhebung, keine Werbung, inklusive Offline-Demomodus."
        ),
    },
    "es-ES": {
        "name": "AGY Remote",
        "subtitle": "Control remoto Antigravity",
        "promotionalText": "Herramienta auxiliar para Antigravity en Mac, creada para cuentas de regiones sin función de control remoto móvil (requiere Antigravity en Mac).",
        "keywords": "antigravity,control remoto,ia programación,tailscale,diff código,desarrollador,agente,mac",
        "whatsNew": "• Versión inicial: Conexión a Antigravity en Mac mediante LAN y Tailscale\n• Visualización de conversaciones de Antigravity, razonamiento y cuota del modelo\n• Aprobación remota de comandos de terminal y planes de implementación\n• Modo Demo sin conexión e interfaz en 12 idiomas",
        "description": (
            "[Nota importante antes de descargar]\n"
            "AGY Remote es un cliente auxiliar independiente de terceros desarrollado exclusivamente para la aplicación de escritorio Antigravity. Dado que las cuentas de Antigravity en algunas regiones no ofrecen la función de control remoto móvil (Remote Control), esta herramienta permite consultar y controlar tus sesiones de Antigravity en Mac desde un iPhone o iPad. Si no utilizas Antigravity en Mac, esta aplicación no te resultará útil.\n\n"
            "• Sincronización con Antigravity: Muestra conversaciones por proyecto, pasos de razonamiento, llamadas a herramientas y el estado de cuota de 5 horas y 1 semana del modelo actual.\n"
            "• Aprobaciones y modos: Permite aprobar o rechazar comandos de terminal, confirmar planes, cambiar el modo de permisos (Review / Auto / Turbo) o detener tareas en curso.\n"
            "• Diffs de código y documentos: Agrupa los planes en Markdown y los archivos modificados en una tarjeta plegable dentro de la conversación.\n"
            "• Conexión y privacidad: Comunicación directa entre tu dispositivo iOS y el servicio de código abierto en tu Mac por LAN o Tailscale, sin recopilación de datos ni anuncios, e incluye un modo de demostración sin conexión."
        ),
    },
    "ru": {
        "name": "AGY Remote",
        "subtitle": "Пульт для Antigravity на Mac",
        "promotionalText": "Вспомогательный клиент для Antigravity на Mac, созданный для аккаунтов тех регионов, где недоступно мобильное управление (требуется Antigravity).",
        "keywords": "antigravity,удаленное управление,ии код,tailscale,diff кода,разработка,агент,терминал,mac",
        "whatsNew": "• Первый выпуск: Подключение к Antigravity на Mac по LAN и Tailscale\n• Отображение диалогов Antigravity, шагов рассуждений и лимитов модели\n• Удаленное подтверждение команд терминала и планов реализации\n• Автономный демо-режим и интерфейс на 12 языках",
        "description": (
            "[Важное примечание перед загрузкой]\n"
            "AGY Remote — это независимый сторонний вспомогательный клиент, разработанный специально для настольной среды Antigravity. Поскольку для аккаунтов Antigravity в некоторых регионах функция мобильного удаленного управления (Remote Control) не предоставляется, это приложение создано для просмотра и управления сессиями Antigravity на Mac с iPhone или iPad. Если вы не пользуетесь Antigravity на Mac, это приложение будет для вас бесполезным.\n\n"
            "• Синхронизация с Antigravity: Отображает список диалогов по проектам, ход рассуждений, вызовы инструментов, а также остаток квоты выбранной модели на 5 часов и 1 неделю.\n"
            "• Удаленное подтверждение: Позволяет одобрять или отклонять команды терминала и планы, переключать режимы разрешений (Review / Auto / Turbo) и останавливать текущую задачу.\n"
            "• Изменения кода и документы: Планы в формате Markdown и измененные файлы группируются в сворачиваемую карточку внутри диалога.\n"
            "• Подключение и конфиденциальность: Прямое соединение по LAN или Tailscale с локальной службой на вашем Mac. Без рекламы, без сбора данных и со встроенным демо-режимом."
        ),
    },
    "pt-BR": {
        "name": "AGY Remote",
        "subtitle": "Controle para Antigravity",
        "promotionalText": "Ferramenta auxiliar para o Antigravity no Mac, voltada a contas de regiões sem controle remoto móvel (requer o uso do Antigravity no seu Mac).",
        "keywords": "antigravity,controle remoto,programação ia,tailscale,diff código,desenvolvedor,agente,mac",
        "whatsNew": "• Versão inicial: Conexão ao Antigravity no Mac via LAN e Tailscale\n• Exibição das conversas do Antigravity, raciocínio, ferramentas e cotas do modelo\n• Aprovação remota de comandos de terminal e planos de implementação\n• Modo Demo offline integrado e suporte a 12 idiomas",
        "description": (
            "[Aviso importante antes de baixar]\n"
            "O AGY Remote é um cliente auxiliar independente de terceiros desenvolvido exclusivamente para o aplicativo de desktop Antigravity. Como as contas do Antigravity em algumas regiões não oferecem o recurso de controle remoto móvel (Remote Control), esta ferramenta foi criada para visualizar e controlar suas sessões do Antigravity no Mac a partir do iPhone ou iPad. Se você não utiliza o Antigravity no Mac, este aplicativo não terá utilidade para você.\n\n"
            "• Sincronização com o Antigravity: Exibe conversas organizadas por projeto, etapas de raciocínio, chamadas de ferramentas e a cota restante de 5 horas e 1 semana do modelo selecionado.\n"
            "• Aprovações e modos: Permite aprovar ou rejeitar comandos de terminal, confirmar planos, alternar modos de permissão (Review / Auto / Turbo) e interromper tarefas em execução.\n"
            "• Diffs de código e documentos: Agrupa documentos de plano e arquivos modificados em um cartão recolhível dentro da conversa.\n"
            "• Conexão e privacidade: Comunicação direta via LAN ou Tailscale com o serviço de código aberto no seu Mac. Sem coleta de dados, sem anúncios e com modo de demonstração offline incluso."
        ),
    },
    "it": {
        "name": "AGY Remote",
        "subtitle": "Controllo per Antigravity",
        "promotionalText": "Strumento ausiliario per Antigravity su Mac, pensato per gli account di regioni prive di controllo remoto mobile (richiede Antigravity su Mac).",
        "keywords": "antigravity,controllo remoto,programmazione ia,tailscale,diff codice,sviluppatore,agente,mac",
        "whatsNew": "• Versione iniziale: Connessione ad Antigravity su Mac tramite LAN e Tailscale\n• Visualizzazione di conversazioni Antigravity, ragionamento e quote del modello\n• Approvazione remota di comandi da terminale e piani di implementazione\n• Modalità Demo offline e interfaccia in 12 lingue",
        "description": (
            "[Nota importante prima del download]\n"
            "AGY Remote è un client ausiliario indipendente di terze parti sviluppato esclusivamente per l'applicazione desktop Antigravity. Poiché gli account Antigravity di alcune regioni non dispongono della funzione di controllo remoto mobile (Remote Control), questo strumento permette di consultare e gestire le sessioni di Antigravity sul proprio Mac da iPhone e iPad. Se non utilizzi Antigravity su Mac, questa applicazione non ti sarà utile.\n\n"
            "• Sincronizzazione con Antigravity: Mostra le conversazioni divise per progetto, i passaggi di ragionamento, le chiamate agli strumenti e la quota residua (5 ore e 1 settimana) del modello selezionato.\n"
            "• Approvazioni e modalità: Permette di approvare o rifiutare comandi da terminale, confermare piani, cambiare la modalità di autorizzazione (Review / Auto / Turbo) o interrompere l'attività in corso.\n"
            "• Diff del codice e documenti: Raggruppa i documenti di pianificazione e i file modificati in una scheda comprimibile all'interno della chat.\n"
            "• Connessione e privacy: Comunicazione diretta tramite LAN o Tailscale con il servizio open-source sul proprio Mac. Nessuna raccolta dati, nessuna pubblicità e modalità demo offline inclusa."
        ),
    },
    "ar-SA": {
        "name": "AGY Remote",
        "subtitle": "تحكم عن بُعد لـ Antigravity",
        "promotionalText": "أداة مساعدة لبرنامج Antigravity على Mac، مخصصة لحسابات المناطق التي لا تتوفر فيها ميزة التحكم عن بُعد عبر الهاتف (يتطلب Antigravity على Mac).",
        "keywords": "antigravity,تحكم عن بعد,برمجة ذكاء اصطناعي,tailscale,مقارنة كود,أدوات مطورين,وكيل ذكي,ماك",
        "whatsNew": "• الإصدار الأول: الاتصال ببرنامج Antigravity على Mac عبر الشبكة المحلية وTailscale\n• عرض محادثات Antigravity وخطوات التفكير واستدعاء الأدوات وحصة النموذج\n• الموافقة عن بُعد على أوامر الطرفية وخطط التنفيذ\n• وضع تجريبي يعمل دون اتصال ودعم 12 لغة",
        "description": (
            "[ملاحظة هامة قبل التنزيل]\n"
            "تطبيق AGY Remote هو أداة مساعدة مستقلة من طرف ثالث صُممت خصيصاً لبرنامج Antigravity المكتبي. نظراً لأن حسابات Antigravity في بعض المناطق لا تتوفر فيها ميزة التحكم عن بُعد من الهاتف (Remote Control)، تم إنشاء هذا التطبيق ليتيح للمستخدمين متابعة جلسات Antigravity على جهاز Mac والتحكم بها من خلال iPhone أو iPad. إذا لم تكن تستخدم برنامج Antigravity على جهاز Mac، فلن يفيدك هذا التطبيق.\n\n"
            "• مزامنة جلسات Antigravity: عرض المحادثات مصنفة حسب المشروع، وخطوات التفكير، واستدعاء الأدوات، وحصة الاستخدام المتبقية للنموذج (5 ساعات وأسبوع واحد).\n"
            "• الاعتماد عن بُعد وتبديل الأوضاع: قبول أو رفض أوامر الطرفية، وتأكيد خطط العمل، وتغيير وضع الصلاحيات (Review / Auto / Turbo) أو إيقاف المهمة الجارية.\n"
            "• فروقات الكود والمستندات: تجميع مستندات التخطيط والملفات المعدّلة في بطاقة قابلة للطي داخل المحادثة.\n"
            "• الاتصال والخصوصية: اتصال مباشر عبر الشبكة المحلية أو Tailscale بالخدمة المحلية على جهاز Mac الخاص بك، دون جمع أي بيانات أو إعلانات، مع توفر وضع تجريبي يعمل دون اتصال."
        ),
    },
}
