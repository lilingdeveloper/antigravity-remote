//
//  LocalizationManager.swift
//  AntigravityRemote
//
//  Created for App Store Connect 12-language localization support.
//

import Foundation
import SwiftUI
import Combine

public enum AppLanguage: String, CaseIterable, Identifiable {
    case system = "system"
    case zhHans = "zh-Hans"
    case zhHant = "zh-Hant"
    case en = "en"
    case ja = "ja"
    case ko = "ko"
    case fr = "fr"
    case de = "de"
    case es = "es"
    case ru = "ru"
    case pt = "pt"
    case it = "it"
    case ar = "ar"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return "跟随系统 (System Default)"
        case .zhHans: return "简体中文"
        case .zhHant: return "繁體中文"
        case .en: return "English"
        case .ja: return "日本語"
        case .ko: return "한국어"
        case .fr: return "Français"
        case .de: return "Deutsch"
        case .es: return "Español"
        case .ru: return "Русский"
        case .pt: return "Português"
        case .it: return "Italiano"
        case .ar: return "العربية"
        }
    }
}

public final class LocalizationManager: ObservableObject {
    public static let shared = LocalizationManager()

    @Published public var currentLanguage: AppLanguage = .system {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: "app_selected_language_v1")
            updateResolvedLanguage()
        }
    }

    @Published public private(set) var resolvedLanguage: String = "zh-Hans"

    public init() {
        // 优先检查启动参数 (方便自动化测试与营销截图脚本快速切换语言: -app_selected_language_v1 en)
        let args = ProcessInfo.processInfo.arguments
        if let idx = args.firstIndex(of: "-app_selected_language_v1"), idx + 1 < args.count {
            let langArg = args[idx + 1]
            if let lang = AppLanguage(rawValue: langArg) {
                self.currentLanguage = lang
                updateResolvedLanguage()
                return
            }
        }

        // 其次读取 UserDefaults
        if let saved = UserDefaults.standard.string(forKey: "app_selected_language_v1"),
           let lang = AppLanguage(rawValue: saved) {
            self.currentLanguage = lang
        } else {
            self.currentLanguage = .system
        }
        updateResolvedLanguage()
    }

    private func updateResolvedLanguage() {
        if currentLanguage == .system {
            let pref = Locale.preferredLanguages.first ?? "zh-Hans"
            if pref.hasPrefix("zh-Hant") || pref.hasPrefix("zh-HK") || pref.hasPrefix("zh-TW") {
                resolvedLanguage = "zh-Hant"
            } else if pref.hasPrefix("zh") {
                resolvedLanguage = "zh-Hans"
            } else if pref.hasPrefix("ja") {
                resolvedLanguage = "ja"
            } else if pref.hasPrefix("ko") {
                resolvedLanguage = "ko"
            } else if pref.hasPrefix("fr") {
                resolvedLanguage = "fr"
            } else if pref.hasPrefix("de") {
                resolvedLanguage = "de"
            } else if pref.hasPrefix("es") {
                resolvedLanguage = "es"
            } else if pref.hasPrefix("ru") {
                resolvedLanguage = "ru"
            } else if pref.hasPrefix("pt") {
                resolvedLanguage = "pt"
            } else if pref.hasPrefix("it") {
                resolvedLanguage = "it"
            } else if pref.hasPrefix("ar") {
                resolvedLanguage = "ar"
            } else {
                resolvedLanguage = "en"
            }
        } else {
            resolvedLanguage = currentLanguage.rawValue
        }
    }

    public func t(_ zhHans: String) -> String {
        guard resolvedLanguage != "zh-Hans" else { return zhHans }
        if let dict = translations[zhHans] {
            if let target = dict[resolvedLanguage], !target.isEmpty {
                return target
            }
            if let fallbackEn = dict["en"], !fallbackEn.isEmpty {
                return fallbackEn
            }
        }
        return zhHans
    }

    // MARK: - 12 国语言完备翻译字典
    private let translations: [String: [String: String]] = [
        // 底部 Tab
        "远程对话": [
            "zh-Hant": "遠端對話", "en": "Chat", "ja": "チャット", "ko": "대화",
            "fr": "Discussion", "de": "Chat", "es": "Chat", "ru": "Чат",
            "pt": "Chat", "it": "Chat", "ar": "محادثة"
        ],
        "代码变更": [
            "zh-Hant": "代碼變更", "en": "Diffs", "ja": "差分", "ko": "코드 변경",
            "fr": "Diffs", "de": "Änderungen", "es": "Cambios", "ru": "Изменения",
            "pt": "Alterações", "it": "Modifiche", "ar": "تغييرات الكود"
        ],
        "方案文档": [
            "zh-Hant": "方案文檔", "en": "Artifacts", "ja": "成果物", "ko": "산출물",
            "fr": "Artéfacts", "de": "Artefakte", "es": "Artefactos", "ru": "Артефакты",
            "pt": "Artefatos", "it": "Artefatti", "ar": "المستندات"
        ],
        "设置": [
            "zh-Hant": "設定", "en": "Settings", "ja": "設定", "ko": "설정",
            "fr": "Réglages", "de": "Einstellungen", "es": "Ajustes", "ru": "Настройки",
            "pt": "Ajustes", "it": "Impostazioni", "ar": "الإعدادات"
        ],

        // 顶部状态栏与胶囊
        "思考过程": [
            "zh-Hant": "思考過程", "en": "Thinking Process", "ja": "思考プロセス", "ko": "사고 과정",
            "fr": "Réflexion", "de": "Denkprozess", "es": "Razonamiento", "ru": "Размышление",
            "pt": "Raciocínio", "it": "Ragionamento", "ar": "عملية التفكير"
        ],
        "跟随电脑端当前会话模型": [
            "zh-Hant": "跟隨電腦端當前會話模型", "en": "Follow Mac Active Session Model", "ja": "Macの現在のセッションモデルに従う", "ko": "Mac 현재 세션 모델 따르기",
            "fr": "Suivre le modèle actif sur Mac", "de": "Aktuellem Mac-Sitzungsmodell folgen", "es": "Seguir modelo activo del Mac", "ru": "Следовать модели сессии Mac",
            "pt": "Seguir modelo ativo do Mac", "it": "Segui modello attivo su Mac", "ar": "اتباع نموذج جلسة Mac الحالي"
        ],
        "5小时额度": [
            "zh-Hant": "5小時額度", "en": "5h Quota", "ja": "5時間枠", "ko": "5시간 할당량",
            "fr": "Quota 5h", "de": "5h-Kontingent", "es": "Cuota 5h", "ru": "Квота 5ч",
            "pt": "Cota 5h", "it": "Quota 5h", "ar": "حصة 5 ساعات"
        ],
        "周额度": [
            "zh-Hant": "週額度", "en": "Weekly", "ja": "週間枠", "ko": "주간 할당량",
            "fr": "Hebdo", "de": "Wöchentlich", "es": "Semanal", "ru": "Недельная",
            "pt": "Semanal", "it": "Settimanale", "ar": "الحصة الأسبوعية"
        ],
        "选择 AI 模型与额度": [
            "zh-Hant": "選擇 AI 模型與額度", "en": "AI Models & Quotas", "ja": "AIモデルと残り枠", "ko": "AI 모델 및 할당량",
            "fr": "Modèles IA et Quotas", "de": "KI-Modelle & Kontingente", "es": "Modelos de IA y Cuotas", "ru": "Модели ИИ и квоты",
            "pt": "Modelos de IA e Cotas", "it": "Modelli IA e Quote", "ar": "نماذج الذكاء الاصطناعي والحصص"
        ],
        "完成": [
            "zh-Hant": "完成", "en": "Done", "ja": "完了", "ko": "완료",
            "fr": "Terminé", "de": "Fertig", "es": "Listo", "ru": "Готово",
            "pt": "Concluído", "it": "Fine", "ar": "تم"
        ],
        "上下文": [
            "zh-Hant": "上下文", "en": "Context", "ja": "コンテキスト", "ko": "컨텍스트",
            "fr": "Contexte", "de": "Kontext", "es": "Contexto", "ru": "Контекст",
            "pt": "Contexto", "it": "Contesto", "ar": "السياق"
        ],
        "选择模型": [
            "zh-Hant": "選擇模型", "en": "Select Model", "ja": "モデル選択", "ko": "모델 선택",
            "fr": "Choisir modèle", "de": "Modell wählen", "es": "Elegir modelo", "ru": "Выбрать модель",
            "pt": "Escolher modelo", "it": "Scegli modello", "ar": "اختر النموذج"
        ],
        "停止": [
            "zh-Hant": "停止", "en": "Stop", "ja": "停止", "ko": "중지",
            "fr": "Arrêter", "de": "Stopp", "es": "Detener", "ru": "Стоп",
            "pt": "Parar", "it": "Stop", "ar": "إيقاف"
        ],
        "未连接 Mac": [
            "zh-Hant": "未連線 Mac", "en": "Mac Disconnected", "ja": "Mac 未接続", "ko": "Mac 미연결",
            "fr": "Mac déconnecté", "de": "Mac getrennt", "es": "Mac desconectado", "ru": "Mac отключен",
            "pt": "Mac desconectado", "it": "Mac disconnesso", "ar": "Mac غير متصل"
        ],
        "正在自动重连...": [
            "zh-Hant": "正在自動重連...", "en": "Reconnecting...", "ja": "再接続中...", "ko": "재연결 중...",
            "fr": "Reconnexion...", "de": "Wiederverbinden...", "es": "Reconectando...", "ru": "Переподключение...",
            "pt": "Reconectando...", "it": "Riconnessione...", "ar": "جارٍ إعادة الاتصال..."
        ],
        "未选择工作区": [
            "zh-Hant": "未選擇工作區", "en": "No Workspace", "ja": "ワークスペース未選択", "ko": "작업영역 없음",
            "fr": "Aucun espace", "de": "Kein Workspace", "es": "Sin espacio", "ru": "Нет рабочей области",
            "pt": "Sem espaço", "it": "Nessun workspace", "ar": "لا توجد مساحة عمل"
        ],
        "Tailscale · 4ms": [
            "zh-Hant": "Tailscale · 4ms", "en": "Tailscale · 4ms", "ja": "Tailscale · 4ms", "ko": "Tailscale · 4ms",
            "fr": "Tailscale · 4ms", "de": "Tailscale · 4ms", "es": "Tailscale · 4ms", "ru": "Tailscale · 4ms",
            "pt": "Tailscale · 4ms", "it": "Tailscale · 4ms", "ar": "Tailscale · 4ms"
        ],
        "演示模式 · 离线交互": [
            "zh-Hant": "示範模式 · 離線互動", "en": "Demo Mode · Interactive", "ja": "デモモード · オフライン", "ko": "데모 모드 · 오프라인",
            "fr": "Mode démo · Interactif", "de": "Demo-Modus · Interaktiv", "es": "Modo Demo · Interactivo", "ru": "Демо · Интерактив",
            "pt": "Modo Demo · Interativo", "it": "Modalità Demo · Interattiva", "ar": "وضع العرض التوضيحي"
        ],

        // 演示模式横幅与按钮
        "🎮 体验交互演示模式（无需连接 Mac）": [
            "zh-Hant": "🎮 體驗互動示範模式（無需連線 Mac）", "en": "🎮 Try Interactive Demo (No Mac Needed)",
            "ja": "🎮 インタラクティブデモを試す（Mac 接続不要）", "ko": "🎮 인터랙티브 데모 체험 (Mac 연결 불필요)",
            "fr": "🎮 Essayer la démo (Sans Mac)", "de": "🎮 Interaktive Demo testen (Ohne Mac)",
            "es": "🎮 Probar demo interactiva (Sin Mac)", "ru": "🎮 Попробовать демо (Без Mac)",
            "pt": "🎮 Experimentar Demo (Sem Mac)", "it": "🎮 Prova Demo Interattiva (Senza Mac)",
            "ar": "🎮 تجربة العرض التفاعلي (بدون Mac)"
        ],
        "正在体验演示模式（可发送消息、审批命令、查看代码变更）": [
            "zh-Hant": "正在體驗示範模式（可傳送訊息、審批命令、查看代碼變更）",
            "en": "Running in Demo Mode (Send messages, approve commands, inspect diffs)",
            "ja": "デモモード実行中（メッセージ送信、コマンド承認、差分確認が可能）",
            "ko": "데모 모드 체험 중 (메시지 전송, 명령 승인, 코드 변경 검토 가능)",
            "fr": "Mode démo actif (Envoyer messages, approuver commandes, voir diffs)",
            "de": "Demo-Modus aktiv (Nachrichten senden, Befehle genehmigen, Diffs ansehen)",
            "es": "Modo demo activo (Enviar mensajes, aprobar comandos, ver diffs)",
            "ru": "Демо-режим активен (Отправка сообщений, одобрение команд, просмотр diff)",
            "pt": "Modo demo ativo (Enviar mensagens, aprovar comandos, ver diffs)",
            "it": "Modalità demo attiva (Invia messaggi, approva comandi, visualizza diff)",
            "ar": "وضع العرض التوضيحي نشط (إرسال رسائل، موافقة على الأوامر، فحص التغييرات)"
        ],
        "退出演示": [
            "zh-Hant": "退出示範", "en": "Exit Demo", "ja": "デモ終了", "ko": "데모 종료",
            "fr": "Quitter démo", "de": "Demo beenden", "es": "Salir de demo", "ru": "Выйти из демо",
            "pt": "Sair do Demo", "it": "Esci da demo", "ar": "إنهاء العرض"
        ],
        "触发审批演示": [
            "zh-Hant": "觸發審批示範", "en": "Trigger Approval Demo", "ja": "承認デモをトリガー", "ko": "승인 데모 실행",
            "fr": "Déclencher approbation", "de": "Genehmigung testen", "es": "Activar aprobación", "ru": "Запустить одобрение",
            "pt": "Acionar aprovação", "it": "Attiva approvazione", "ar": "تشغيل تجربة الموافقة"
        ],

        // 首次向导横幅与 Tailscale 横幅
        "首次使用？点击查看「2 步极简连接 Mac 教程」": [
            "zh-Hant": "首次使用？點擊查看「2 步極簡連線 Mac 教學」",
            "en": "First time? Tap for '2-Step Mac Setup Guide'",
            "ja": "初めてですか？「2ステップMac接続ガイド」はこちら",
            "ko": "처음이신가요? '2단계 초간편 Mac 연결 가이드' 보기",
            "fr": "Première utilisation ? 'Guide de connexion Mac en 2 étapes'",
            "de": "Neu hier? Tippen für die '2-Schritte Mac-Anleitung'",
            "es": "¿Primera vez? Ver 'Guía de 2 pasos para conectar Mac'",
            "ru": "Впервые? Нажмите для 'Руководства по подключению Mac в 2 шага'",
            "pt": "Primeira vez? Toque para o 'Guia de Conexão Mac em 2 Etapas'",
            "it": "Prima volta? Tocca per 'Guida in 2 passaggi per connettere il Mac'",
            "ar": "أول مرة؟ اضغط لعرض 'دليل الاتصال بجهاز Mac في خطوتين'"
        ],
        "2 步极简连接 Mac": [
            "zh-Hant": "2 步極簡連線 Mac",
            "en": "2-Step Easy Mac Connect",
            "ja": "2ステップ簡単Mac接続",
            "ko": "2단계 초간편 Mac 연결",
            "fr": "Connexion Mac facile en 2 étapes",
            "de": "2-Schritte Mac-Verbindung",
            "es": "Conexión fácil a Mac en 2 pasos",
            "ru": "Подключение к Mac в 2 шага",
            "pt": "Conexão fácil ao Mac em 2 etapas",
            "it": "Connessione facile al Mac in 2 passaggi",
            "ar": "اتصال سهل بجهاز Mac في خطوتين"
        ],
        "一键复制 Mac 安装命令": [
            "zh-Hant": "一鍵複製 Mac 安裝指令",
            "en": "Copy Mac Install Command",
            "ja": "Macインストールコマンドをコピー",
            "ko": "Mac 설치 명령어 복사",
            "fr": "Copier la commande d'installation Mac",
            "de": "Mac-Installationsbefehl kopieren",
            "es": "Copiar comando de instalación de Mac",
            "ru": "Скопировать команду установки для Mac",
            "pt": "Copiar comando de instalação do Mac",
            "it": "Copia comando di installazione per Mac",
            "ar": "نسخ أمر تثبيت Mac"
        ],
        "打开相机扫描 Mac 二维码": [
            "zh-Hant": "開啟相機掃描 Mac QR Code",
            "en": "Scan Mac QR Code with Camera",
            "ja": "カメラでMacのQRコードをスキャン",
            "ko": "카메라로 Mac QR 코드 스캔",
            "fr": "Scanner le QR code Mac avec l'appareil photo",
            "de": "Mac-QR-Code mit Kamera scannen",
            "es": "Escanear código QR de Mac con la cámara",
            "ru": "Сканировать QR-код Mac камерой",
            "pt": "Escanear código QR do Mac com a câmera",
            "it": "Scansiona il codice QR del Mac con la fotocamera",
            "ar": "امسح رمز QR الخاص بـ Mac بالكاميرا"
        ],
        "查看详细图文步骤": [
            "zh-Hant": "查看詳細圖文步驟",
            "en": "View Detailed Guide",
            "ja": "詳細ガイドを見る",
            "ko": "상세 가이드 보기",
            "fr": "Voir le guide détaillé",
            "de": "Detaillierte Anleitung ansehen",
            "es": "Ver guía detallada",
            "ru": "Посмотреть подробное руководство",
            "pt": "Ver guia detalhado",
            "it": "Visualizza guida dettagliata",
            "ar": "عرض الدليل التفصيلي"
        ],
        "内置 Tailscale 尚未登录账号 (异地/5G 穿透需登录一次)": [
            "zh-Hant": "內建 Tailscale 尚未登入帳號 (異地/5G 穿透需登入一次)",
            "en": "Embedded Tailscale not signed in (Required for 5G/remote access)",
            "ja": "内蔵 Tailscale 未ログイン（リモート/5Gアクセスにログインが必要）",
            "ko": "내장 Tailscale 미로그인 (원격/5G 접속 시 1회 로그인 필요)",
            "fr": "Tailscale intégré non connecté (Requis pour l'accès distant 5G)",
            "de": "Integriertes Tailscale nicht angemeldet (Erforderlich für Fernzugriff)",
            "es": "Tailscale integrado sin sesión (Requerido para acceso remoto/5G)",
            "ru": "Встроенный Tailscale не авторизован (Требуется для удаленного доступа)",
            "pt": "Tailscale integrado desconectado (Necessário para acesso remoto/5G)",
            "it": "Tailscale integrato non connesso (Richiesto per accesso remoto 5G)",
            "ar": "Tailscale المدمج غير مسجل الدخول (مطلوب للاتصال عن بعد)"
        ],
        "立即登录 →": [
            "zh-Hant": "立即登入 →", "en": "Sign In Now →", "ja": "今すぐログイン →", "ko": "지금 로그인 →",
            "fr": "Se connecter →", "de": "Jetzt anmelden →", "es": "Iniciar sesión →", "ru": "Войти →",
            "pt": "Entrar agora →", "it": "Accedi ora →", "ar": "سجّل الدخول الآن →"
        ],

        // 聊天页与审批卡片
        "AI 正在思考 · Working...": [
            "zh-Hant": "AI 正在思考 · Working...", "en": "AI is thinking · Working...",
            "ja": "AI が思考中 · 作業中...", "ko": "AI 생각 중 · 작업 중...",
            "fr": "L'IA réfléchit · En cours...", "de": "KI denkt nach · Arbeitet...",
            "es": "La IA está pensando · Trabajando...", "ru": "ИИ думает · Работает...",
            "pt": "IA pensando · Trabalhando...", "it": "L'IA sta pensando · In corso...",
            "ar": "الذكاء الاصطناعي يفكر..."
        ],
        "快捷远程指令": [
            "zh-Hant": "快捷遠端指令", "en": "Quick Commands", "ja": "クイックコマンド", "ko": "빠른 원격 명령",
            "fr": "Commandes rapides", "de": "Schnellbefehle", "es": "Comandos rápidos", "ru": "Быстрые команды",
            "pt": "Comandos rápidos", "it": "Comandi rapidi", "ar": "أوامر سريعة"
        ],
        "终端命令待审批": [
            "zh-Hant": "終端機命令待審批", "en": "Shell Command Pending Approval", "ja": "ターミナルコマンドの承認待ち", "ko": "터미널 명령 승인 대기",
            "fr": "Commande Shell en attente", "de": "Terminal-Befehl wartet auf Freigabe", "es": "Comando Shell pendiente de aprobación", "ru": "Команда терминала ожидает одобрения",
            "pt": "Comando do terminal aguardando aprovação", "it": "Comando Shell in attesa di approvazione", "ar": "أمر الطرفية بانتظار الموافقة"
        ],
        "实施方案待审批": [
            "zh-Hant": "實施方案待審批", "en": "Plan Pending Approval", "ja": "計画の承認待ち", "ko": "구현 계획 승인 대기",
            "fr": "Plan en attente d'approbation", "de": "Plan wartet auf Freigabe", "es": "Plan pendiente de aprobación", "ru": "План ожидает одобрения",
            "pt": "Plano aguardando aprovação", "it": "Piano in attesa di approvazione", "ar": "خطة العمل بانتظار الموافقة"
        ],
        "AI 提问待回答": [
            "zh-Hant": "AI 提問待回答", "en": "Question Pending Answer", "ja": "AI からの質問に回答待ち", "ko": "AI 질문 답변 대기",
            "fr": "Question en attente de réponse", "de": "Frage wartet auf Antwort", "es": "Pregunta pendiente de respuesta", "ru": "Вопрос ожидает ответа",
            "pt": "Pergunta aguardando resposta", "it": "Domanda in attesa di risposta", "ar": "سؤال بانتظار الإجابة"
        ],
        "拒绝 (Reject)": [
            "zh-Hant": "拒絕 (Reject)", "en": "Reject", "ja": "拒否 (Reject)", "ko": "거부 (Reject)",
            "fr": "Rejeter", "de": "Ablehnen", "es": "Rechazar", "ru": "Отклонить",
            "pt": "Rejeitar", "it": "Rifiuta", "ar": "رفض"
        ],
        "批准执行 (Approve)": [
            "zh-Hant": "批准執行 (Approve)", "en": "Approve", "ja": "承認して実行 (Approve)", "ko": "승인 및 실행 (Approve)",
            "fr": "Approuver", "de": "Genehmigen", "es": "Aprobar", "ru": "Одобрить",
            "pt": "Aprovar", "it": "Approva", "ar": "موافقة"
        ],
        "批准方案并继续 (Proceed)": [
            "zh-Hant": "批准方案並繼續 (Proceed)", "en": "Proceed", "ja": "計画を承認して続行 (Proceed)", "ko": "계획 승인 및 계속 (Proceed)",
            "fr": "Continuer (Proceed)", "de": "Fortfahren (Proceed)", "es": "Continuar (Proceed)", "ru": "Продолжить (Proceed)",
            "pt": "Continuar (Proceed)", "it": "Procedi (Proceed)", "ar": "متابعة التنفيذ"
        ],
        "向电脑端 Antigravity 发送指令...": [
            "zh-Hant": "向電腦端 Antigravity 傳送指令...", "en": "Send instruction to Mac Antigravity...",
            "ja": "MacのAntigravityに指示を送信...", "ko": "Mac의 Antigravity로 지시 전송...",
            "fr": "Envoyer une instruction à Antigravity...", "de": "Anweisung an Antigravity auf Mac senden...",
            "es": "Enviar instrucción a Antigravity en Mac...", "ru": "Отправить команду в Antigravity на Mac...",
            "pt": "Enviar instrução para o Antigravity no Mac...", "it": "Invia istruzione ad Antigravity su Mac...",
            "ar": "أرسل توجيهات إلى Antigravity على Mac..."
        ],

        // 代码变更与方案文档
        "当前对话暂无文件修改记录": [
            "zh-Hant": "目前對話暫無檔案修改記錄", "en": "No file changes in this session",
            "ja": "このセッションでのファイル変更はありません", "ko": "이 세션에서 변경된 파일이 없습니다",
            "fr": "Aucune modification de fichier", "de": "Keine Dateiänderungen in dieser Sitzung",
            "es": "No hay cambios de archivo en esta sesión", "ru": "Нет изменений файлов в этой сессии",
            "pt": "Nenhuma alteração de arquivo nesta sessão", "it": "Nessuna modifica ai file in questa sessione",
            "ar": "لا توجد تعديلات على الملفات في هذه المحادثة"
        ],
        "复制全文": [
            "zh-Hant": "複製全文", "en": "Copy All", "ja": "すべてコピー", "ko": "전체 복사",
            "fr": "Tout copier", "de": "Alles kopieren", "es": "Copiar todo", "ru": "Копировать все",
            "pt": "Copiar tudo", "it": "Copia tutto", "ar": "نسخ الكل"
        ],
        "当前对话暂无方案文档 (Artifact)": [
            "zh-Hant": "目前對話暫無方案文檔 (Artifact)", "en": "No artifacts in this session",
            "ja": "このセッションの成果物はありません", "ko": "이 세션의 산출물이 없습니다",
            "fr": "Aucun artéfact dans cette session", "de": "Keine Artefakte in dieser Sitzung",
            "es": "No hay artefactos en esta sesión", "ru": "Нет артефактов в этой сессии",
            "pt": "Nenhum artefato nesta sessão", "it": "Nessun artefatto in questa sessione",
            "ar": "لا توجد مستندات خطة في هذه الجلسة"
        ],
        "复制": [
            "zh-Hant": "複製", "en": "Copy", "ja": "コピー", "ko": "복사",
            "fr": "Copier", "de": "Kopieren", "es": "Copiar", "ru": "Копировать",
            "pt": "Copiar", "it": "Copia", "ar": "نسخ"
        ],

        // 设置页各分组与主要设置项
        "界面语言 / Language": [
            "zh-Hant": "介面語言 / Language", "en": "Language", "ja": "言語 / Language", "ko": "언어 / Language",
            "fr": "Langue / Language", "de": "Sprache / Language", "es": "Idioma / Language", "ru": "Язык / Language",
            "pt": "Idioma / Language", "it": "Lingua / Language", "ar": "اللغة / Language"
        ],
        "对话流展示设置": [
            "zh-Hant": "對話流展示設定", "en": "Chat Stream Display", "ja": "チャットストリーム表示設定", "ko": "대화 스트림 표시 설정",
            "fr": "Affichage du flux de discussion", "de": "Chat-Stream Anzeige", "es": "Visualización del chat", "ru": "Отображение потока чата",
            "pt": "Exibição do fluxo de chat", "it": "Visualizzazione chat", "ar": "إعدادات عرض المحادثة"
        ],
        "展示 AI 思考过程 (Thinking)": [
            "zh-Hant": "展示 AI 思考過程 (Thinking)", "en": "Show AI Thinking Process", "ja": "AI思考プロセスを表示", "ko": "AI 생각 과정 표시",
            "fr": "Afficher le processus de réflexion", "de": "KI-Denkprozess anzeigen", "es": "Mostrar pensamiento de IA", "ru": "Показывать ход мыслей ИИ",
            "pt": "Mostrar pensamento da IA", "it": "Mostra ragionamento IA", "ar": "عرض تفكير الذكاء الاصطناعي"
        ],
        "默认自动展开思考过程": [
            "zh-Hant": "預設自動展開思考過程", "en": "Auto-expand Thinking by Default", "ja": "思考プロセスをデフォルトで展開", "ko": "생각 과정 기본 자동 펼치기",
            "fr": "Développer automatiquement la réflexion", "de": "Denkprozess standardmäßig aufklappen", "es": "Auto-expandir pensamiento por defecto", "ru": "Автоматически раскрывать ход мыслей",
            "pt": "Autoexpandir pensamento por padrão", "it": "Espandi automaticamente il ragionamento", "ar": "توسيع التفكير تلقائياً"
        ],
        "展示读取文件记录 (read_file)": [
            "zh-Hant": "展示讀取檔案記錄 (read_file)", "en": "Show File Read Calls (read_file)", "ja": "ファイル読込履歴を表示 (read_file)", "ko": "파일 읽기 호출 표시 (read_file)",
            "fr": "Afficher les lectures de fichiers (read_file)", "de": "Datei-Lesezugriffe anzeigen (read_file)", "es": "Mostrar lecturas de archivo (read_file)", "ru": "Показывать вызовы read_file",
            "pt": "Mostrar leitura de arquivos (read_file)", "it": "Mostra chiamate read_file", "ar": "عرض سجلات قراءة الملفات"
        ],
        "展示命令执行与修改文件记录": [
            "zh-Hant": "展示命令執行與修改檔案記錄", "en": "Show Tool Calls (edit_file / commands)", "ja": "ツール呼出履歴を表示 (コマンド/編集)", "ko": "명령 실행 및 파일 수정 호출 표시",
            "fr": "Afficher les appels d'outils", "de": "Befehls- und Dateiänderungen anzeigen", "es": "Mostrar llamadas a herramientas", "ru": "Показывать выполнение команд и правок",
            "pt": "Mostrar execuções de comandos e edições", "it": "Mostra esecuzione comandi e modifiche", "ar": "عرض سجلات تشغيل الأوامر والتعديل"
        ],
        "展示上下文容量进度条": [
            "zh-Hant": "展示上下文容量進度條", "en": "Show Context Usage Bar", "ja": "コンテキスト容量バーを表示", "ko": "컨텍스트 용량 프로그레스 바 표시",
            "fr": "Afficher la barre d'utilisation du contexte", "de": "Kontext-Auslastungsleiste anzeigen", "es": "Mostrar barra de capacidad de contexto", "ru": "Показывать шкалу контекста",
            "pt": "Mostrar barra de uso do contexto", "it": "Mostra barra di utilizzo contesto", "ar": "عرض شريط سعة السياق"
        ],
        "消息队列与多端协同": [
            "zh-Hant": "訊息佇列與多端協同", "en": "Message Queue & Multi-device Sync", "ja": "メッセージキュー＆複数端末連携", "ko": "메시지 대기열 및 다중 기기 동기화",
            "fr": "File d'attente et synchronisation", "de": "Warteschlange & Gerätesynchronisierung", "es": "Cola de mensajes y sincronización", "ru": "Очередь сообщений и синхронизация",
            "pt": "Fila de mensagens e sincronização", "it": "Coda messaggi e sincronizzazione", "ar": "قائمة انتظار الرسائل ومزامنة الأجهزة"
        ],
        "发送多条消息自动排队": [
            "zh-Hant": "傳送多條訊息自動排隊", "en": "Queue Multiple Messages When Busy", "ja": "生成中のメッセージを自動キューイング", "ko": "생성 중 추가 메시지 자동 대기열 추가",
            "fr": "Mettre en file d'attente si occupé", "de": "Nachrichten einreihen, wenn beschäftigt", "es": "Encolar mensajes cuando esté ocupado", "ru": "Очередь сообщений при занятости",
            "pt": "Enfileirar mensagens quando ocupado", "it": "Metti in coda i messaggi se occupato", "ar": "ترتيب الرسائل تلقائياً أثناء الانشغال"
        ],
        "自动跟随电脑端新建对话": [
            "zh-Hant": "自動跟隨電腦端新建對話", "en": "Auto-follow New Conversations on Mac", "ja": "Macでの新規会話に自動追従", "ko": "Mac에서 새 대화 생성 시 자동 전환",
            "fr": "Suivre automatiquement les nouvelles discussions", "de": "Neuen Chats auf dem Mac automatisch folgen", "es": "Seguir automáticamente nuevas conversaciones", "ru": "Следовать за новыми диалогами на Mac",
            "pt": "Seguir automaticamente novas conversas no Mac", "it": "Segui automaticamente nuove chat su Mac", "ar": "متابعة المحادثات الجديدة تلقائياً"
        ],
        "扫码配对、Tailscale 组网与连接设置": [
            "zh-Hant": "掃碼配對、Tailscale 組網與連線設定", "en": "Pairing, Tailscale & Connection", "ja": "QRペアリング・Tailscale・接続設定", "ko": "QR 페어링, Tailscale 및 연결 설정",
            "fr": "Appairage QR, Tailscale & Connexion", "de": "QR-Kopplung, Tailscale & Verbindung", "es": "Emparejamiento QR, Tailscale y conexión", "ru": "QR-сопряжение, Tailscale и подключение",
            "pt": "Pareamento QR, Tailscale e Conexão", "it": "Accoppiamento QR, Tailscale e connessione", "ar": "المسح الضوئي و Tailscale وإعدادات الاتصال"
        ],
        "扫码一键配对连接 (/qr)": [
            "zh-Hant": "掃碼一鍵配對連線 (/qr)", "en": "Scan QR Code to Connect (/qr)", "ja": "QRコードで簡単ペアリング (/qr)", "ko": "QR 코드로 간편 페어링 (/qr)",
            "fr": "Scanner le QR code (/qr)", "de": "QR-Code scannen zum Verbinden (/qr)", "es": "Escanear código QR (/qr)", "ru": "Сканировать QR для подключения (/qr)",
            "pt": "Escanear QR Code para conectar (/qr)", "it": "Scansiona QR code per connettere (/qr)", "ar": "مسح الرمز للربط (/qr)"
        ],
        "通道与连接高级设置": [
            "zh-Hant": "通道與連線進階設定", "en": "Advanced Connection Settings", "ja": "接続の詳細設定", "ko": "고급 연결 설정",
            "fr": "Paramètres de connexion avancés", "de": "Erweiterte Verbindungseinstellungen", "es": "Ajustes avanzados de conexión", "ru": "Расширенные настройки подключения",
            "pt": "Configurações avançadas de conexão", "it": "Impostazioni di connessione avanzate", "ar": "إعدادات الاتصال المتقدمة"
        ],
        "Mac 桥接服务器参数": [
            "zh-Hant": "Mac 橋接伺服器參數", "en": "Mac Host Server Config", "ja": "Mac ホストサーバー設定", "ko": "Mac 호스트 서버 설정",
            "fr": "Configuration du serveur Mac", "de": "Mac Host-Server Konfiguration", "es": "Configuración del servidor Mac", "ru": "Конфигурация Mac-сервера",
            "pt": "Configuração do servidor Mac", "it": "Configurazione server host Mac", "ar": "إعدادات خادم Mac"
        ],
        "保存地址并立即重连": [
            "zh-Hant": "儲存位址並立即重連", "en": "Save & Reconnect Now", "ja": "保存して今すぐ再接続", "ko": "저장 후 즉시 재연결",
            "fr": "Enregistrer et reconnecter", "de": "Speichern & jetzt verbinden", "es": "Guardar y reconectar ahora", "ru": "Сохранить и переподключиться",
            "pt": "Salvar e reconectar agora", "it": "Salva e riconnetti ora", "ar": "حفظ وإعادة الاتصال فوراً"
        ],
        "隐私声明与关于": [
            "zh-Hant": "隱私權聲明與關於", "en": "Privacy & About", "ja": "プライバシーと情報", "ko": "개인정보 처리방침 및 정보",
            "fr": "Confidentialité et à propos", "de": "Datenschutz & Über", "es": "Privacidad y acerca de", "ru": "Конфиденциальность и инфо",
            "pt": "Privacidade e Sobre", "it": "Privacy e info", "ar": "الخصوصية وحول التطبيق"
        ],
        "隐私政策 (Privacy Policy)": [
            "zh-Hant": "隱私權政策 (Privacy Policy)", "en": "Privacy Policy", "ja": "プライバシーポリシー", "ko": "개인정보 처리방침 (Privacy Policy)",
            "fr": "Politique de confidentialité", "de": "Datenschutzerklärung", "es": "Política de privacidad", "ru": "Политика конфиденциальности",
            "pt": "Política de Privacidade", "it": "Informativa sulla privacy", "ar": "سياسة الخصوصية"
        ],
        "开源组件许可 (Open Source Licenses)": [
            "zh-Hant": "開源組件授權 (Open Source Licenses)", "en": "Open Source Licenses", "ja": "オープンソースライセンス", "ko": "오픈소스 라이선스",
            "fr": "Licences open source", "de": "Open-Source-Lizenzen", "es": "Licencias de código abierto", "ru": "Лицензии открытого ПО",
            "pt": "Licenças de código aberto", "it": "Licenze Open Source", "ar": "تراخيص المصدر المفتوح"
        ],
        "进入交互式演示模式 (Demo Mode)": [
            "zh-Hant": "進入互動式示範模式 (Demo Mode)", "en": "Enter Interactive Demo Mode", "ja": "インタラクティブデモモードに入る", "ko": "인터랙티브 데모 모드 진입",
            "fr": "Activer le mode démo interactif", "de": "Interaktiven Demo-Modus starten", "es": "Entrar en modo demo interactivo", "ru": "Войти в интерактивный демо-режим",
            "pt": "Entrar no modo demo interativo", "it": "Entra in modalità demo interattiva", "ar": "الدخول إلى وضع العرض التوضيحي"
        ]
    ]
}

public func L(_ text: String) -> String {
    LocalizationManager.shared.t(text)
}
