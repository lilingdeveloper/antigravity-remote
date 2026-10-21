# -*- coding: utf-8 -*-
"""AGY Remote 12 国语言 App Store 截图海报文案
场景顺序固定: chat, approval, diffs, models
每项: (徽标, 大标题, 副标题)
"""
SCENES = ["chat", "approval", "diffs", "models"]

COPY = {
    "zh-Hans": [
        ("VIBE CODING · 随身编码", "手机远程掌控 AI 编程工作区", "思考过程、工具调用、上下文容量进度条与代码高亮实时流式同步"),
        ("远程权限审批 · 一键放行", "终端命令与方案，掌上一键审批", "出门在外也能随时 Approve 终端命令、确认实施方案，开发流永不卡壳"),
        ("代码变更 · 方案文档", "Diffs 与架构文档，清晰预览", "随时随地检视每一行代码改动与 Markdown 计划书，一键复制全文"),
        ("免公网 IP · 内置 TAILSCALE", "扫码即连，多模型配额一目了然", "内置 Tailscale 穿透与局域网双路毫秒级竞速，实时查看模型额度"),
    ],
    "zh-Hant": [
        ("VIBE CODING · 隨身編碼", "手機遠端掌控 AI 程式工作區", "思考過程、工具呼叫、上下文容量進度條與程式碼高亮即時串流同步"),
        ("遠端權限審批 · 一鍵放行", "終端機指令與方案，掌上一鍵審批", "出門在外也能隨時 Approve 終端指令、確認實施方案，開發流永不中斷"),
        ("程式碼變更 · 方案文件", "Diffs 與架構文件，清晰預覽", "隨時隨地檢視每一行程式碼改動與 Markdown 計畫書，一鍵複製全文"),
        ("免公網 IP · 內建 TAILSCALE", "掃碼即連，多模型配額一目瞭然", "內建 Tailscale 穿透與區域網路雙路毫秒級競速，即時查看模型額度"),
    ],
    "en": [
        ("VIBE CODING · ON THE GO", "Control your AI IDE from iPhone", "Live thinking streams, tool calls, context usage bar, and syntax-highlighted code."),
        ("REMOTE APPROVALS · 1-TAP", "Approve commands & plans anywhere", "Review terminal commands and implementation plans on the go so agents never stall."),
        ("CODE DIFFS · ARTIFACTS", "Inspect code changes & docs clearly", "Browse file diffs and Markdown design artifacts anytime with one-tap copy."),
        ("NO PUBLIC IP · TAILSCALE", "Scan QR to pair, track model quotas", "Built-in Tailscale mesh + LAN racing with real-time 5-hour & weekly model quotas."),
    ],
    "ja": [
        ("VIBE CODING · 外出先でも", "スマホから AI 開発環境を遠隔操作", "思考プロセス、ツール呼び出し、コンテキスト使用率、コードハイライトをリアルタイム同期。"),
        ("リモート承認 · ワンタップ", "コマンドと計画を外出先で即承認", "ターミナル実行や実装プランをスマホから承認し、AI エージェントの作業を止めません。"),
        ("コード差分 · 設計ドキュメント", "Diff と Markdown 文書を鮮明に確認", "変更されたコードや計画書をいつでもプレビューし、ワンタップでコピー可能。"),
        ("公開 IP 不要 · TAILSCALE 内蔵", "QR で即ペアリング、モデル残量も把握", "内蔵 Tailscale と LAN 高速ルーティングに加え、各 AI モデルの残り枠を一目で確認。"),
    ],
    "ko": [
        ("VIBE CODING · 모바일 원격 제어", "아이폰으로 AI 코딩 워크스페이스 제어", "사고 과정, 도구 호출, 컨텍스트 용량 바 및 코드 하이라이팅을 실시간 스트리밍 동기화."),
        ("원격 권한 승인 · 원탭 처리", "터미널 명령 및 구현 계획 즉시 승인", "외출 중에도 터미널 명령과 실행 계획을 승인하여 개발 워크플로우가 멈추지 않습니다."),
        ("코드 변경 · 아티팩트 문서", "코드 Diff와 설계 문서를 한눈에", "수정된 소스 코드와 마크다운 계획서를 언제 어디서나 검토하고 원탭으로 복사하세요."),
        ("공인 IP 불필요 · TAILSCALE 내장", "QR 스캔 간편 연결 및 모델 할당량 확인", "내장 Tailscale 및 LAN 듀얼 라우팅과 모델별 잔여 사용량을 실시간으로 확인하세요."),
    ],
    "fr": [
        ("VIBE CODING · EN MOBILITÉ", "Pilotez votre IDE IA depuis l'iPhone", "Flux de réflexion, appels d'outils, jauge de contexte et code coloré en temps réel."),
        ("APPROBATION À DISTANCE", "Validez commandes et plans en un geste", "Approuvez les commandes terminal et plans d'action où que vous soyez, sans blocage."),
        ("DIFFS DE CODE · ARTIFACTS", "Examinez vos modifications et documents", "Consultez chaque fichier modifié et vos plans Markdown avec copie instantanée."),
        ("SANS IP PUBLIQUE · TAILSCALE", "Appairage QR et suivi des quotas IA", "Tailscale intégré + routage LAN ultra-rapide et suivi en direct des quotas de modèles."),
    ],
    "de": [
        ("VIBE CODING · UNTERWEGS", "Steuere deine KI-IDE direkt vom iPhone", "Denkprozesse, Tool-Aufrufe, Kontext-Fortschrittsbalken und Code-Highlighting in Echtzeit."),
        ("FERNFREIGABE · EIN TIPP", "Befehle & Pläne überall freigeben", "Bestätige Terminal-Befehle und Architekturpläne von unterwegs ohne Unterbrechung."),
        ("CODE-DIFFS · DOKUMENTE", "Code-Änderungen & Pläne klar prüfen", "Prüfe Dateiänderungen und Markdown-Dokumente jederzeit mit Ein-Tipp-Kopierfunktion."),
        ("OHNE ÖFFENTLICHE IP · TAILSCALE", "QR-Pairing & Modell-Kontingente im Blick", "Integriertes Tailscale + LAN-Routing sowie Live-Anzeige deiner KI-Modellkontingente."),
    ],
    "es": [
        ("VIBE CODING · EN CUALQUIER LUGAR", "Controla tu IDE de IA desde el iPhone", "Proceso de pensamiento, llamadas a herramientas, barra de contexto y código en vivo."),
        ("APROBACIÓN REMOTA · 1 TOQUE", "Aprueba comandos y planes al instante", "Autoriza comandos de terminal y planes de implementación sin detener tu flujo."),
        ("DIFFS DE CÓDIGO · DOCUMENTOS", "Revisa cambios de código y artefactos", "Inspecciona cada archivo modificado y planes en Markdown con copia en un toque."),
        ("SIN IP PÚBLICA · TAILSCALE", "Empareja con QR y revisa cuotas de IA", "Tailscale integrado + ruta rápida LAN y monitoreo en vivo de cuotas de modelos."),
    ],
    "ru": [
        ("VIBE CODING · В ЛЮБОМ МЕСТЕ", "Управляйте ИИ-средой с iPhone", "Поток размышлений, вызовы инструментов, шкала контекста и подсветка кода в реальном времени."),
        ("УДАЛЁННОЕ ОДОБРЕНИЕ", "Подтверждайте команды и планы в 1 касание", "Разрешайте терминальные команды и планы реализации на ходу без остановки агента."),
        ("DIFF КОДА · АРТЕФАКТЫ", "Просматривайте изменения и документацию", "Проверяйте изменённые файлы и планы в Markdown с мгновенным копированием."),
        ("БЕЗ ПУБЛИЧНОГО IP · TAILSCALE", "QR-сопряжение и квоты ИИ-моделей", "Встроенный Tailscale + быстрый LAN и отслеживание лимитов моделей в реальном времени."),
    ],
    "pt": [
        ("VIBE CODING · NO CELULAR", "Controle seu IDE de IA pelo iPhone", "Fluxo de raciocínio, chamadas de ferramentas, barra de contexto e código em tempo real."),
        ("APROVAÇÃO REMOTA · 1 TOQUE", "Aprove comandos e planos de onde estiver", "Autorize comandos de terminal e planos de implementação sem travar seu fluxo."),
        ("DIFFS DE CÓDIGO · ARTEFATOS", "Revise alterações de código e documentos", "Inspecione arquivos modificados e planos em Markdown com cópia em um toque."),
        ("SEM IP PÚBLICO · TAILSCALE", "Pareie via QR e acompanhe cotas de IA", "Tailscale integrado + roteamento LAN rápido e visão em tempo real das cotas de modelos."),
    ],
    "it": [
        ("VIBE CODING · IN MOBILITÀ", "Controlla il tuo IDE IA da iPhone", "Flusso di pensiero, chiamate agli strumenti, barra del contesto e codice in tempo reale."),
        ("APPROVAZIONE REMOTA · 1 TOCCO", "Approva comandi e piani ovunque", "Autorizza comandi da terminale e piani di implementazione senza interrompere il lavoro."),
        ("DIFF DEL CODICE · ARTEFATTI", "Esamina modifiche al codice e documenti", "Controlla i file modificati e i documenti Markdown con copia immediata."),
        ("SENZA IP PUBBLICO · TAILSCALE", "Accoppia via QR e monitora le quote IA", "Tailscale integrato + routing LAN veloce e stato in tempo reale delle quote dei modelli."),
    ],
    "ar": [
        ("برمجة بالذكاء الاصطناعي عن بُعد", "تحكّم في بيئة تطوير الذكاء الاصطناعي من iPhone", "مزامنة فورية لعملية التفكير واستدعاء الأدوات وشريط سعة السياق وتنسيق الأكواد."),
        ("موافقة عن بُعد بنقرة واحدة", "اعتمد أوامر الطرفية والخطط من أي مكان", "وافق على تنفيذ الأوامر وخطط العمل أثناء تنقلك دون توقف سير العمل."),
        ("فروقات الكود والوثائق", "استعرض تعديلات الأكواد ومستندات التصميم", "راجع جميع الملفات المعدّلة وخطط Markdown بوضوح مع إمكانية النسخ الفوري."),
        ("دون IP عام · TAILSCALE مدمج", "اقتران سريع عبر QR ومتابعة حصص النماذج", "محرك Tailscale مدمج مع اتصال شبكي فائق السرعة وعرض مباشر لحصص نماذج الذكاء الاصطناعي."),
    ],
}
