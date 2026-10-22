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
        "subtitle": "AI 编程工作区移动远程控制",
        "promotionalText": "专为 Vibe Coding 打造的随身远程控制端！内置 Tailscale 免公网穿透，支持思考流同步、远程命令审批、代码 Diff 预览与上下文容量监控。",
        "keywords": "vibe coding,远程控制,AI编程,tailscale,代码对比,开发者工具,终端审批,agent,开发助手,mac远程",
        "whatsNew": "• 首发上线：支持局域网与内置 Tailscale 双通道毫秒级直连 Mac 工作区\n• 实时流式同步 AI 思考过程、工具调用胶丸、上下文容量进度条与代码高亮\n• 支持手机端远程一键审批终端命令 (Approve/Reject) 与实施方案 (Proceed)\n• 内置免连接交互式演示模式 (Demo Mode) 与 12 国语言支持",
        "description": (
            "在 Vibe Coding 时代，越来越多开发者使用 AI Agent 自动编写代码、运行测试与重构架构。然而当离开电脑前、出门在外或躺在沙发上时，如果电脑端的 Agent 卡在「等待终端命令审批」或需要确认下一阶段方案，开发流程就会被迫中断。\n\n"
            "AGY Remote 专为解决这一痛点而生！它将您 Mac 上的 AI 编程工作区完整映射到 iPhone 与 iPad 上，提供丝滑的原生流式对话、远程权限审批与代码检视体验。\n\n"
            "【毫秒级双擎流式对话】\n"
            "• 实时展示 AI 思考过程（Thinking 折叠/展开卡片）、工具调用记录（读取文件、修改代码、执行命令）与 Markdown 代码高亮卡片。\n"
            "• 标题栏下方实时显示当前对话上下文容量百分比与 Token 消耗进度条。\n"
            "• 智能消息排队：当 AI 正在思考或执行任务时，新发送的消息可自动进入待发送队列依次执行，绝不打断当前推理。\n\n"
            "【远程权限审批 · 开发流永不卡壳】\n"
            "• 电脑端触发终端命令确认（Approve / Reject）、实施方案确认（Proceed）或多选题交互时，手机端即时弹出审批卡片，一键放行。\n\n"
            "【代码变更 (Diffs) 与方案文档 (Artifacts)】\n"
            "• 随时在手机上检视当前会话修改的每一个源代码文件与 Markdown 架构方案文档，支持一键复制全文。\n\n"
            "【内置 Tailscale 免公网 IP · 扫码即连】\n"
            "• 内置多路并发竞速路由（Happy Eyeballs）：自动在局域网极速直连与 Tailscale 虚拟局域网穿透之间无缝切换。\n"
            "• 内置免连接「交互式演示模式 (Demo Mode)」，无需配置电脑即可直接体验完整功能。\n\n"
            "【零数据收集 · 纯粹点对点隐私安全】\n"
            "• 无广告、无统计追踪、无需注册账号，所有数据仅在您的 iOS 设备与您本人的 Mac 之间点对点直连传输。"
        ),
    },
    "zh-Hant": {
        "name": "AGY Remote",
        "subtitle": "AI 程式工作區行動遠端控制",
        "promotionalText": "專為 Vibe Coding 打造的隨身遠端控制端！內建 Tailscale 免公網穿透，支援思考流同步、遠端指令審批、程式碼 Diff 預覽與上下文容量監控。",
        "keywords": "vibe coding,遠端控制,AI程式,tailscale,程式碼對比,開發者工具,終端審批,agent,開發助手,mac遠端",
        "whatsNew": "• 首發上線：支援區域網路與內建 Tailscale 雙通道毫秒級直連 Mac 工作區\n• 即時串流同步 AI 思考過程、工具呼叫、上下文容量進度條與程式碼高亮\n• 支援手機端遠端一鍵審批終端機指令與實施方案\n• 內建免連線互動式示範模式 (Demo Mode) 與 12 國語言支援",
        "description": (
            "在 Vibe Coding 時代，越來越多開發者使用 AI Agent 自動編寫程式碼、執行測試與重構架構。然而當離開電腦前或出門在外時，若電腦端的 Agent 等待終端機指令審批或方案確認，開發流程就會被迫中斷。\n\n"
            "AGY Remote 將您 Mac 上的 AI 程式開發工作區完整延伸至 iPhone 與 iPad，提供流暢的原生串流對話、遠端權限審批與程式碼檢視體驗。\n\n"
            "【毫秒級串流對話與上下文監控】\n"
            "• 即時顯示 AI 思考過程、工具呼叫記錄、上下文 Token 容量進度條與語法高亮程式碼區塊。\n"
            "• 支援訊息智慧排隊：AI 忙碌時新發送的指令自動排隊依序執行。\n\n"
            "【遠端指令與方案一鍵審批】\n"
            "• 手機端即時彈出終端機指令 (Approve / Reject) 與實施方案 (Proceed) 審批卡片，隨時隨地一鍵放行。\n\n"
            "【程式碼變更 (Diffs) 與方案文件 (Artifacts)】\n"
            "• 隨時檢視修改的原始碼差異與 Markdown 計畫文件，支援一鍵複製。\n\n"
            "【內建 Tailscale 免公網 IP · 零資料收集】\n"
            "• 支援區域網路與 Tailscale 雙通道自動競速切換，並提供離線互動示範模式 (Demo Mode)。無廣告、無追蹤，純點對點加密直連。"
        ),
    },
    "en-US": {
        "name": "AGY Remote",
        "subtitle": "Remote Control for AI Coding",
        "promotionalText": "Control your Mac AI coding workspace from iPhone & iPad! Live thinking streams, remote command approvals, code diffs, context meter, and built-in Tailscale.",
        "keywords": "vibe coding,remote control,ai coding,tailscale,code diff,developer tools,agent,ide remote,mac",
        "whatsNew": "• Initial release: Multi-path low-latency connection over LAN and built-in Tailscale\n• Live streaming AI thinking cards, tool call pills, context capacity bar & code blocks\n• One-tap remote approval for terminal commands and implementation plans\n• Built-in interactive offline Demo Mode and 12-language localization",
        "description": (
            "In the era of Vibe Coding, AI agents write code, run tests, and refactor projects autonomously. Yet when you step away from your desk, your workflow often stalls waiting for a terminal command approval or plan confirmation.\n\n"
            "AGY Remote brings your Mac AI coding workspace directly to your iPhone and iPad with native streaming performance, instant remote approvals, and full code diff inspection.\n\n"
            "[Real-Time Streaming Chat & Context Meter]\n"
            "• Watch live AI thinking processes, categorized tool calls (read_file, edit_file, run_command), and syntax-highlighted code blocks.\n"
            "• Monitor real-time conversation context window usage (percentage & token count) right below the title bar.\n"
            "• Smart Message Queueing: Queue follow-up prompts while the agent is busy so tasks execute sequentially without interruption.\n\n"
            "[One-Tap Remote Approvals]\n"
            "• Approve or reject terminal commands, confirm implementation plans (Proceed), and answer agent questions from anywhere.\n\n"
            "[Code Diffs & Markdown Artifacts]\n"
            "• Inspect modified source files and architecture plans on the go with one-tap copy.\n\n"
            "[Built-in Tailscale & Interactive Demo Mode]\n"
            "• Happy Eyeballs multi-route engine races LAN direct and Tailscale mesh connections automatically.\n"
            "• Includes a full interactive offline Demo Mode so you can explore every feature immediately without connecting a Mac.\n\n"
            "[Zero Data Collection & Peer-to-Peer Privacy]\n"
            "• Zero tracking, no ads, and no third-party analytics. All traffic flows directly between your iOS device and your own Mac."
        ),
    },
    "ja": {
        "name": "AGY Remote",
        "subtitle": "AI開発環境のモバイル遠隔操作",
        "promotionalText": "Mac上のAIコーディング環境をiPhone/iPadから遠隔操作！思考ストリーム、コマンド承認、コード差分(Diff)、コンテキスト残量表示、Tailscale内蔵。",
        "keywords": "vibe coding,リモート操作,AI開発,tailscale,コード差分,開発ツール,エージェント,ターミナル承認,mac連携",
        "whatsNew": "• 初回リリース：LANおよび内蔵Tailscaleによるミリ秒単位の高速接続\n• AI思考プロセス、ツール呼び出し、コンテキスト容量バー、コードブロックのリアルタイム同期\n• ターミナルコマンドや実装計画のリモート承認機能\n• Mac不要で試せるインタラクティブ・デモモードと12言語対応",
        "description": (
            "AIエージェントを活用した「Vibe Coding」では、席を離れた間にコマンド実行の承認待ちで作業が止まってしまうことがあります。\n\n"
            "AGY Remoteは、Mac上のAI開発ワークスペースをiPhoneやiPadへシームレスに拡張し、外出先からでも思考ストリームの確認、コマンド承認、コード差分のレビューを可能にするネイティブアプリです。\n\n"
            "【リアルタイム対話ストリーム＆コンテキスト監視】\n"
            "• AIの思考プロセス（折りたたみ/展開）、ツール呼び出し、シンタックスハイライト付きコードをリアルタイム表示。\n"
            "• コンテキスト使用率（％およびトークン数）をプログレスバーで常時把握。\n\n"
            "【リモート承認で作業を止めない】\n"
            "• ターミナルコマンドの許可/拒否（Approve/Reject）や計画書の承認（Proceed）をスマホからワンタップで処理。\n\n"
            "【コード差分(Diffs)とドキュメント(Artifacts)】\n"
            "• 変更されたソースコードやMarkdownの設計書をいつでもプレビュー・コピー可能。\n\n"
            "【Tailscale内蔵・デモモード搭載・完全プライベート】\n"
            "• LANとTailscaleを自動切り替え。Mac未接続でもすぐ試せるデモモードを搭載。広告・追跡ゼロのP2P直接通信。"
        ),
    },
    "ko": {
        "name": "AGY Remote",
        "subtitle": "AI 코딩 워크스페이스 모바일 원격 제어",
        "promotionalText": "Mac의 AI 코딩 환경을 iPhone과 iPad에서 원격 제어하세요! 실시간 사고 과정 스트리밍, 명령 승인, 코드 Diff 확인 및 내장 Tailscale 지원.",
        "keywords": "vibe coding,원격제어,AI코딩,tailscale,코드비교,개발자도구,에이전트,터미널승인,맥원격",
        "whatsNew": "• 첫 출시: LAN 및 내장 Tailscale 듀얼 채널 초저지연 연결\n• AI 사고 과정, 도구 호출, 컨텍스트 용량 바 및 코드 블록 실시간 스트리밍\n• 원격 터미널 명령 및 실행 계획 원탭 승인\n• Mac 연결 없이 바로 체험 가능한 인터랙티브 데모 모드 및 12개 국어 지원",
        "description": (
            "AI 에이전트와 함께하는 Vibe Coding 시대에 자리를 비웠을 때 터미널 명령 승인 대기 때문에 작업이 멈춘 적이 있으신가요?\n\n"
            "AGY Remote는 Mac의 AI 개발 워크스페이스를 iPhone 및 iPad로 연결하여 언제 어디서나 실시간 추론 스트림 확인, 권한 승인, 코드 변경 검토를 지원하는 네이티브 리모트 앱입니다.\n\n"
            "[실시간 스트리밍 대화 및 컨텍스트 용량 바]\n"
            "• AI 사고 과정(Thinking), 도구 호출 기록, 코드 하이라이팅 및 컨텍스트 토큰 사용률을 실시간으로 표시합니다.\n"
            "• 스마트 메시지 대기열: AI가 작업 중일 때 보낸 메시지를 자동으로 큐에 넣어 순차적으로 실행합니다.\n\n"
            "[원탭 원격 승인]\n"
            "• 터미널 명령 실행(Approve/Reject) 및 구현 계획(Proceed)을 모바일에서 즉시 승인하세요.\n\n"
            "[코드 Diff 및 아티팩트 문서 프리뷰]\n"
            "• 수정된 파일과 마크다운 계획서를 한눈에 비교하고 원탭으로 복사할 수 있습니다.\n\n"
            "[내장 Tailscale & 오프라인 데모 모드 & 철저한 프라이버시]\n"
            "• 공인 IP 없이도 QR 스캔으로 간편하게 연결되며, 즉시 체험 가능한 데모 모드를 제공합니다. 광고 및 데이터 수집 제로."
        ),
    },
    "fr-FR": {
        "name": "AGY Remote",
        "subtitle": "Contrôle distant pour IDE IA",
        "promotionalText": "Pilotez votre espace de codage IA Mac depuis iPhone et iPad ! Flux de réflexion en direct, approbation de commandes, diffs de code et Tailscale intégré.",
        "keywords": "vibe coding,contrôle distant,codage ia,tailscale,diff code,outils dev,agent,terminal,mac",
        "whatsNew": "• Version initiale : Connexion ultra-rapide via LAN et Tailscale intégré\n• Flux de réflexion IA, appels d'outils, jauge de contexte et blocs de code en direct\n• Approbation à distance en un geste des commandes terminal et plans d'action\n• Mode Démo interactif hors-ligne intégré et support de 12 langues",
        "description": (
            "AGY Remote prolonge votre espace de développement IA Mac sur iPhone et iPad. Suivez les réflexions de votre agent en temps réel, approuvez les commandes terminal à distance et inspectez vos diffs de code où que vous soyez.\n\n"
            "• Flux en temps réel : Cartes de réflexion IA, appels d'outils, barre d'utilisation du contexte et coloration syntaxique.\n"
            "• Approbations à distance : Validez ou refusez les commandes terminal et plans d'implémentation en un toucher.\n"
            "• Diffs & Artifacts : Consultez les fichiers modifiés et documents d'architecture Markdown.\n"
            "• Tailscale intégré & Mode Démo : Connexion directe P2P sans IP publique, plus un Mode Démo interactif sans Mac requis. Zéro pistage, zéro publicité."
        ),
    },
    "de-DE": {
        "name": "AGY Remote",
        "subtitle": "Fernsteuerung für KI-Coding",
        "promotionalText": "Steuere deinen Mac KI-Coding-Workspace vom iPhone & iPad! Live-Denkprozesse, Befehlsfreigaben, Code-Diffs, Kontext-Anzeige und integriertes Tailscale.",
        "keywords": "vibe coding,fernsteuerung,ki coding,tailscale,code diff,entwickler,agent,terminal,mac",
        "whatsNew": "• Erstveröffentlichung: Schnelle Verbindung über LAN und integriertes Tailscale\n• Live-Streaming für KI-Denkprozesse, Tool-Aufrufe, Kontext-Balken und Codeblöcke\n• Ein-Tipp-Fernfreigabe für Terminal-Befehle und Implementierungspläne\n• Integrierter interaktiver Offline-Demomodus und 12 Sprachen",
        "description": (
            "AGY Remote bringt deinen Mac KI-Entwicklungs-Workspace direkt auf iPhone und iPad. Verfolge Denkprozesse in Echtzeit, gib Terminal-Befehle von unterwegs frei und prüfe Code-Änderungen (Diffs) jederzeit.\n\n"
            "• Echtzeit-Streaming & Kontext-Balken: KI-Denkprozesse, Tool-Aufrufe, Token-Auslastung und Code-Highlighting.\n"
            "• Fernfreigaben mit einem Tipp: Terminal-Befehle (Approve/Reject) und Architekturpläne (Proceed) sofort bestätigen.\n"
            "• Code-Diffs & Dokumente: Geänderte Dateien und Markdown-Pläne übersichtlich prüfen.\n"
            "• Tailscale integriert & Demomodus: Direkte P2P-Verbindung ohne öffentliche IP sowie interaktiver Demomodus ohne Mac. Kein Tracking, keine Werbung."
        ),
    },
    "es-ES": {
        "name": "AGY Remote",
        "subtitle": "Control remoto para IDE de IA",
        "promotionalText": "¡Controla tu espacio de programación IA en Mac desde iPhone y iPad! Flujo de pensamiento en vivo, aprobación de comandos, diffs de código y Tailscale.",
        "keywords": "vibe coding,control remoto,ia programación,tailscale,diff código,desarrollador,agente,mac",
        "whatsNew": "• Lanzamiento inicial: Conexión de baja latencia vía LAN y Tailscale integrado\n• Sincronización en vivo de pensamiento IA, herramientas, barra de contexto y código\n• Aprobación remota en un toque para comandos de terminal y planes\n• Modo Demo interactivo sin conexión y soporte para 12 idiomas",
        "description": (
            "AGY Remote conecta tu espacio de desarrollo IA en Mac con tu iPhone y iPad. Supervisa el razonamiento del agente en tiempo real, aprueba comandos de terminal a distancia y revisa diffs de código desde cualquier lugar.\n\n"
            "• Chat en tiempo real y barra de contexto: Visualiza pensamientos de IA, llamadas a herramientas y uso de tokens.\n"
            "• Aprobaciones remotas: Autoriza o rechaza comandos de terminal y planes de implementación al instante.\n"
            "• Diffs de código y artefactos: Inspecciona archivos modificados y documentos Markdown.\n"
            "• Tailscale integrado y Modo Demo: Conexión P2P directa sin IP pública y Modo Demo interactivo integrado. Cero rastreo y sin anuncios."
        ),
    },
    "ru": {
        "name": "AGY Remote",
        "subtitle": "Пульт для ИИ-среды разработки",
        "promotionalText": "Управляйте ИИ-средой разработки на Mac с iPhone и iPad! Поток размышлений, одобрение команд, просмотр Diff кода, шкала контекста и встроенный Tailscale.",
        "keywords": "vibe coding,удаленное управление,ии код,tailscale,diff кода,разработка,агент,терминал,mac",
        "whatsNew": "• Первый релиз: Быстрое подключение по LAN и через встроенный Tailscale\n• Поток размышлений ИИ, вызовы инструментов, шкала контекста и подсветка кода\n• Удалённое одобрение терминальных команд и планов реализации в одно касание\n• Встроенный интерактивный демо-режим без Mac и поддержка 12 языков",
        "description": (
            "AGY Remote переносит рабочее пространство ИИ-разработки с вашего Mac на iPhone и iPad. Следите за рассуждениями агента, одобряйте команды терминала и проверяйте изменения кода (Diffs) из любой точки мира.\n\n"
            "• Потоковый чат и шкала контекста: Мыслительный процесс ИИ, вызовы инструментов и процент заполнения контекстного окна.\n"
            "• Удалённое подтверждение: Разрешайте или отклоняйте команды терминала и планы реализации одним касанием.\n"
            "• Diff кода и артефакты: Просматривайте изменённые файлы и планы в формате Markdown.\n"
            "• Встроенный Tailscale и Демо-режим: Прямое P2P-соединение без белого IP и полноценный демо-режим. Без рекламы и слежки."
        ),
    },
    "pt-BR": {
        "name": "AGY Remote",
        "subtitle": "Controle Remoto para IDE de IA",
        "promotionalText": "Controle seu workspace de programação IA no Mac pelo iPhone e iPad! Fluxo de raciocínio ao vivo, aprovação de comandos, diffs de código e Tailscale integrado.",
        "keywords": "vibe coding,controle remoto,programação ia,tailscale,diff código,desenvolvedor,agente,mac",
        "whatsNew": "• Lançamento inicial: Conexão rápida via LAN e Tailscale integrado\n• Streaming ao vivo do raciocínio da IA, ferramentas, barra de contexto e código\n• Aprovação remota em um toque para comandos de terminal e planos\n• Modo Demo interativo offline integrado e suporte a 12 idiomas",
        "description": (
            "O AGY Remote leva seu ambiente de desenvolvimento IA do Mac diretamente para o iPhone e iPad. Acompanhe o raciocínio do agente em tempo real, aprove comandos de terminal remotamente e revise diffs de código de onde estiver.\n\n"
            "• Streaming em tempo real e barra de contexto: Veja o processo de pensamento da IA, chamadas de ferramentas e uso de tokens.\n"
            "• Aprovações remotas em 1 toque: Autorize comandos de terminal e planos de implementação sem interromper seu fluxo.\n"
            "• Diffs de código e artefatos: Inspecione arquivos modificados e planos em Markdown.\n"
            "• Tailscale integrado e Modo Demo: Conexão P2P direta sem IP público e Modo Demo interativo sem precisar de Mac. Zero rastreamento e sem anúncios."
        ),
    },
    "it": {
        "name": "AGY Remote",
        "subtitle": "Controllo remoto per IDE IA",
        "promotionalText": "Controlla il tuo workspace di programmazione IA su Mac da iPhone e iPad! Flusso di pensiero live, approvazione comandi, diff del codice e Tailscale integrato.",
        "keywords": "vibe coding,controllo remoto,programmazione ia,tailscale,diff codice,sviluppatore,agente,mac",
        "whatsNew": "• Versione iniziale: Connessione rapida via LAN e Tailscale integrato\n• Streaming live del pensiero IA, chiamate strumenti, barra del contesto e codice\n• Approvazione remota in un tocco per comandi terminale e piani\n• Modalità Demo interattiva offline integrata e supporto per 12 lingue",
        "description": (
            "AGY Remote estende il tuo workspace di sviluppo IA su Mac direttamente su iPhone e iPad. Segui il ragionamento dell'agente in tempo reale, approva i comandi da terminale a distanza ed esamina i diff del codice ovunque ti trovi.\n\n"
            "• Chat in streaming e barra del contesto: Visualizza i processi di pensiero IA, gli strumenti invocati e l'uso dei token.\n"
            "• Approvazioni remote: Autorizza o rifiuta comandi terminale e piani d'azione con un solo tocco.\n"
            "• Diff del codice e artefatti: Controlla i file modificati e i documenti Markdown.\n"
            "• Tailscale integrato e Modalità Demo: Connessione diretta P2P senza IP pubblico e Modalità Demo interattiva integrata. Zero tracciamento e nessuna pubblicità."
        ),
    },
    "ar-SA": {
        "name": "AGY Remote",
        "subtitle": "تحكم عن بُعد لبيئة البرمجة",
        "promotionalText": "تحكّم في مساحة عمل البرمجة بالذكاء الاصطناعي على Mac من iPhone وiPad! بث مباشر للتفكير، اعتماد الأوامر، معاينة فروقات الكود، ومحرك Tailscale مدمج.",
        "keywords": "vibe coding,تحكم عن بعد,برمجة ذكاء اصطناعي,tailscale,مقارنة كود,أدوات مطورين,وكيل ذكي,ماك",
        "whatsNew": "• الإصدار الأول: اتصال فائق السرعة عبر الشبكة المحلية ومحرك Tailscale المدمج\n• مزامنة فورية لعملية تفكير الذكاء الاصطناعي واستدعاء الأدوات وشريط سعة السياق\n• موافقة عن بُعد بنقرة واحدة على أوامر الطرفية وخطط التنفيذ\n• وضع تجريبي تفاعلي مدمج يعمل دون اتصال ودعم 12 لغة",
        "description": (
            "يتيح لك تطبيق AGY Remote التحكم الكامل في مساحة عمل البرمجة بالذكاء الاصطناعي على جهاز Mac مباشرة من iPhone وiPad. تابع خطوات تفكير الوكيل الذكي لحظة بلحظة، واعتمد أوامر الطرفية عن بُعد، وراجع تعديلات الأكواد من أي مكان.\n\n"
            "• محادثة فورية وشريط سعة السياق: عرض عملية التفكير واستدعاء الأدوات ونسبة استهلاك الرموز (Tokens).\n"
            "• موافقات عن بُعد بنقرة واحدة: قبول أو رفض أوامر الطرفية وخطط العمل فوراً.\n"
            "• فروقات الكود والمستندات: استعراض الملفات المعدّلة ووثائق Markdown مع النسخ السريع.\n"
            "• محرك Tailscale مدمج ووضع تجريبي تفاعلي: اتصال مباشر آمن دون IP عام، مع وضع تجريبي متكامل وخصوصية تامة دون إعلانات أو تتبع."
        ),
    },
}
