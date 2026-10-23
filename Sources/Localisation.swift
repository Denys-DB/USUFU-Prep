import Foundation

enum Language: String, Codable, CaseIterable {
    case english = "en"
    case ukrainian = "uk"
    case spanish = "es"
    case portuguese = "pt"

    var title: String {
        switch self {
        case .english: return "English"
        case .ukrainian: return "Українська"
        case .spanish: return "Español"
        case .portuguese: return "Português"
        }
    }

    var badge: String {
        switch self {
        case .english: return "EN"
        case .ukrainian: return "UA"
        case .spanish: return "ES"
        case .portuguese: return "PT"
        }
    }

    var localeIdentifier: String {
        switch self {
        case .english: return "en_GB"
        case .ukrainian: return "uk"
        case .spanish: return "es"
        case .portuguese: return "pt_BR"
        }
    }

    var pluralForms: Int { self == .ukrainian ? 3 : 2 }

    static var systemDefault: Language {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "en"
        for language in allCases where language != .english {
            if preferred.hasPrefix(language.rawValue) { return language }
        }
        return .english
    }
}

func L(_ text: String) -> String { Localisation.t(text) }

func Lf(_ format: String, _ arguments: CVarArg...) -> String {
    String(format: Localisation.declineGroups(Localisation.t(format), arguments),
           arguments: arguments)
}

func Lp(_ count: Int, _ one: String, _ other: String) -> String {
    String(format: Localisation.declined(count, one: one, other: other), count)
}

extension Notification.Name {
    static let usufuLanguageChanged = Notification.Name("usufu.languageChanged")
}

enum Localisation {

    private(set) static var current: Language = .english

    private(set) static var revision = 0

    static func use(_ language: Language) {
        guard language != current else { return }
        current = language
        revision += 1
        NotificationCenter.default.post(name: .usufuLanguageChanged, object: nil)
    }

    static func table(for language: Language) -> [String: String]? {
        switch language {
        case .english: return nil
        case .ukrainian: return ukrainian
        case .spanish: return Spanish.table
        case .portuguese: return Portuguese.table
        }
    }

    static func t(_ text: String) -> String {
        guard let table = table(for: current) else { return text }
        return table[text] ?? text
    }

    static func declined(_ count: Int, one: String, other: String) -> String {
        let n = abs(count)
        if current == .ukrainian, let forms = plurals[other], forms.count == 3 {
            if n % 100 >= 11 && n % 100 <= 14 { return forms[2] }
            switch n % 10 {
            case 1: return forms[0]
            case 2, 3, 4: return forms[1]
            default: return forms[2]
            }
        }
        return t(n == 1 ? one : other)
    }

    static func declineGroups(_ format: String, _ arguments: [CVarArg]) -> String {
        guard format.contains("{") else { return format }

        let positional = format.ranges(ofPattern: #"%(\d+)\$[@dfs]"#)
        var spots: [(Int, Int)] = []
        if !positional.isEmpty {
            for range in positional {
                let text = String(format[range])
                let digits = text.dropFirst().prefix { $0.isNumber }
                let index = (Int(digits) ?? 1) - 1
                spots.append((format.distance(from: format.startIndex,
                                              to: range.lowerBound), index))
            }
        } else {
            for (i, range) in format.ranges(ofPattern: #"%[@dfs]"#).enumerated() {
                spots.append((format.distance(from: format.startIndex,
                                              to: range.lowerBound), i))
            }
        }

        var out = ""
        var rest = Substring(format)
        while let open = rest.firstIndex(of: "{"),
              let close = rest[open...].firstIndex(of: "}") {
            out += rest[..<open]
            let at = format.distance(from: format.startIndex, to: open)
            let body = String(rest[rest.index(after: open)..<close])
            out += pick(body, at: at, spots: spots, arguments: arguments)
            rest = rest[rest.index(after: close)...]
        }
        return out + rest
    }

    private static func pick(_ body: String, at: Int,
                             spots: [(Int, Int)], arguments: [CVarArg]) -> String {
        var body = body
        var governing: Int?
        if let colon = body.firstIndex(of: ":") {
            let head = String(body[..<colon])
            if let named = Int(head), !head.isEmpty {
                governing = named - 1
                body = String(body[body.index(after: colon)...])
            }
        }
        let forms = body.components(separatedBy: "|")
        guard forms.count > 1 else { return forms.first ?? "" }
        if governing == nil {
            for (offset, index) in spots where offset < at { governing = index }
        }
        guard let which = governing, which < arguments.count,
              let n = intValue(arguments[which]) else { return forms.last! }
        let count = abs(n)
        if current == .ukrainian, forms.count >= 3 {
            if count % 100 >= 11 && count % 100 <= 14 { return forms[2] }
            switch count % 10 {
            case 1: return forms[0]
            case 2, 3, 4: return forms[1]
            default: return forms[2]
            }
        }
        return count == 1 ? forms[0] : forms[1]
    }

    private static func intValue(_ value: CVarArg) -> Int? {
        switch value {
        case let n as Int: return n
        case let n as Int32: return Int(n)
        case let n as Int64: return Int(n)
        case let n as UInt: return Int(n)
        case let n as Double: return Int(n)
        default: return nil
        }
    }

    static let plurals: [String: [String]] = [
        "%d answers in this slice":
            ["%d відповідь у цьому зрізі",
             "%d відповіді у цьому зрізі",
             "%d відповідей у цьому зрізі"],
        "The last copy you made was %d days ago.":
            ["Останню копію ви зробили %d день тому.",
             "Останню копію ви зробили %d дні тому.",
             "Останню копію ви зробили %d днів тому."],
        "You were away for %d days.":
            ["Вас не було %d день.", "Вас не було %d дні.", "Вас не було %d днів."],
        "Setting that time aside keeps the run of %d days you had going.":
            ["Якщо відкласти цей час, ваша серія з %d дня триватиме далі.",
             "Якщо відкласти цей час, ваша серія з %d днів триватиме далі.",
             "Якщо відкласти цей час, ваша серія з %d днів триватиме далі."],
        "Set aside %d days":
            ["Відкласти %d день", "Відкласти %d дні", "Відкласти %d днів"],
        "It has been %d days since you last practiced.":
            ["Минув %d день від вашої останньої практики.",
             "Минуло %d дні від вашої останньої практики.",
             "Минуло %d днів від вашої останньої практики."],
        "Includes %d days you set aside":
            ["Включає %d день, який ви відклали",
             "Включає %d дні, які ви відклали",
             "Включає %d днів, які ви відклали"],
        "%d days in a row":
            ["%d день поспіль", "%d дні поспіль", "%d днів поспіль"],
        "questions answered":
            ["відповідь дано", "відповіді дано", "відповідей дано"],
        "days practiced":
            ["день практики", "дні практики", "днів практики"],
        "%d days in a row so far.":
            ["%d день поспіль наразі.", "%d дні поспіль наразі.", "%d днів поспіль наразі."],
        "Answer %d questions to start a streak":
            ["Дайте %d відповідь, щоб почати серію", "Дайте %d відповіді, щоб почати серію", "Дайте %d відповідей, щоб почати серію"],
        "questions kept back":
            ["запитання відкладено", "запитання відкладено",
             "запитань відкладено"],
        "%d decks":
            ["%d колода", "%d колоди", "%d колод"],
        "%d question sets updated":
            ["%d набір запитань оновлено", "%d набори запитань оновлено",
             "%d наборів запитань оновлено"],
        "%d question records":
            ["%d запис про запитання", "%d записи про запитання", "%d записів про запитання"],
        "%d highlights":
            ["%d виділення", "%d виділення", "%d виділень"],
        "%d words without a definition are hidden":
            ["%d слово без визначення приховано", "%d слова без визначення приховано",
             "%d слів без визначення приховано"],
        "%d study plans":
            ["%d план навчання", "%d плани навчання", "%d планів навчання"],
        "%d sets are waiting for their question PDFs.":
            ["%d набір очікує на свій PDF із запитаннями.", "%d набори очікують на свої PDF із запитаннями.", "%d наборів очікують на свої PDF із запитаннями."],
        "%d imported sets are waiting for their question PDFs. Their progress is kept and applied the moment you import them.":
            ["%d імпортований набір очікує на свій PDF із запитаннями. Його прогрес збережено і буде застосовано щойно ви його імпортуєте.", "%d імпортовані набори очікують на свої PDF із запитаннями. Їхній прогрес збережено і буде застосовано щойно ви їх імпортуєте.", "%d імпортованих наборів очікують на свої PDF із запитаннями. Їхній прогрес збережено і буде застосовано щойно ви їх імпортуєте."],
        "%d cards": ["%d картка", "%d картки", "%d карток"],
        "%d files": ["%d файл", "%d файли", "%d файлів"],
        "%d minutes left": ["залишилася %d хвилина", "залишилося %d хвилини",
                            "залишилося %d хвилин"],
        "%d questions": ["%d запитання", "%d запитання", "%d запитань"],
        "%d minutes": ["%d хвилина", "%d хвилини", "%d хвилин"],
        "left off %d days ago": ["зупинились %d день тому", "зупинились %d дні тому",
                                 "зупинились %d днів тому"],
        "%d seconds a side": ["%d секунда на сторону",
                              "%d секунди на сторону",
                              "%d секунд на сторону"],
        "%d words added": ["Додано %d слово", "Додано %d слова", "Додано %d слів"],
        "%d cards deleted": ["Видалено %d картку", "Видалено %d картки",
                             "Видалено %d карток"],
        "%d cards will be removed from this deck.":
            ["З цієї колоди буде видалено %d картку.",
             "З цієї колоди буде видалено %d картки.",
             "З цієї колоди буде видалено %d карток."],
        "%d questions in all": ["%d питання загалом", "%d питання загалом",
                                "%d питань загалом"],
        "%d new": ["%d нове", "%d нових", "%d нових"],
        "%d to review": ["%d на повторення", "%d на повторення", "%d на повторення"],
        "%d words left in this deck": ["у колоді лишилось %d слово",
                                       "у колоді лишилось %d слова",
                                       "у колоді лишилось %d слів"],
        "Finish today's words to make it %d days.":
            ["Завершіть сьогоднішні слова — і буде %d день поспіль.",
             "Завершіть сьогоднішні слова — і буде %d дні поспіль.",
             "Завершіть сьогоднішні слова — і буде %d днів поспіль."],
        "days in a row": ["день поспіль", "дні поспіль", "днів поспіль"],
        "%d more questions keep it.":
            ["Ще %d запитання — і вона збережеться.",
             "Ще %d запитання — і вона збережеться.",
             "Ще %d запитань — і вона збережеться."],
        "%d questions are unanswered":
            ["%d запитання без відповіді",
             "%d запитання без відповіді",
             "%d запитань без відповіді"],
        "%d questions set aside from":
            ["%d запитання відкладено з",
             "%d запитання відкладено з",
             "%d запитань відкладено з"],
        "%d questions to review":
            ["%d запитання для повторення",
             "%d запитання для повторення",
             "%d запитань для повторення"],
        "%d-day streak ends tonight":
            ["Серія з %d дня завершується сьогодні",
             "Серія з %d днів завершується сьогодні",
             "Серія з %d днів завершується сьогодні"],
        "Saved %d questions":
            ["Збережено %d запитання",
             "Збережено %d запитання",
             "Збережено %d запитань"],
        "Today's plan is %d questions.":
            ["План на сьогодні — %d запитання.",
             "План на сьогодні — %d запитання.",
             "План на сьогодні — %d запитань."],
        "You have %d minutes. The clock can be hidden, and it comes back on its own with five minutes left.":
            ["У вас %d хвилина. Годинник можна сховати — він повернеться сам, коли залишиться п'ять хвилин.",
             "У вас %d хвилини. Годинник можна сховати — він повернеться сам, коли залишиться п'ять хвилин.",
             "У вас %d хвилин. Годинник можна сховати — він повернеться сам, коли залишиться п'ять хвилин."],
        "%d more to keep today":
            ["ще %d, щоб утримати сьогодні",
             "ще %d, щоб утримати сьогодні",
             "ще %d, щоб утримати сьогодні"],
        "%d-day streak held · nothing planned today":
            ["Серію з %d дня збережено · на сьогодні нічого не заплановано",
             "Серію з %d днів збережено · на сьогодні нічого не заплановано",
             "Серію з %d днів збережено · на сьогодні нічого не заплановано"],

        "%d questions left today.":
            ["Сьогодні лишилося %d питання.",
             "Сьогодні лишилося %d питання.",
             "Сьогодні лишилося %d питань."],
        "%d days":
            ["%d день",
             "%d дні",
             "%d днів"],
        "%d hours":
            ["%d година",
             "%d години",
             "%d годин"],
        "%d deleted":
            ["%d видалено",
             "%d видалено",
             "%d видалено"],
        "%d questions were skipped:":
            ["%d запитання пропущено:",
             "%d запитання пропущено:",
             "%d запитань пропущено:"],
    ]

    static func hasTranslation(_ text: String) -> Bool { ukrainian[text] != nil }

    static var keys: [String] { Array(ukrainian.keys) }

    static let ukrainian: [String: String] = [
        "This PDF can be read or printed, and imported back into %@ to practice again.":
            "Цей PDF можна читати чи роздрукувати, а також імпортувати назад у %@, щоб потренуватися ще раз.",
        "This PDF can be read or printed, and imported back into %@.":
            "Цей PDF можна читати чи роздрукувати, а також імпортувати назад у %@.",

        "Library": "Бібліотека",
        "Unshelved": "Без полиці",
        "New shelf": "Нова полиця",
        "Rename shelf…": "Перейменувати полицю…",
        "Rename shelf": "Перейменувати полицю",
        "Remove shelf": "Видалити полицю",
        "Move up": "Вгору",
        "Move down": "Вниз",
        "Move to shelf": "Перемістити на полицю",
        "New shelf…": "Нова полиця…",
        "Empty — drag a set here, or use its menu.":
            "Порожньо — перетягніть набір сюди або скористайтеся його меню.",
        "Everything is on a shelf.": "Усе розкладено по полицях.",
        "The sets on it are kept — they go back to Unshelved.":
            "Набори з неї збережуться — вони повернуться до «Без полиці».",
        "Order the sets by": "Упорядкувати набори за",
        "The order I put them in": "Порядком, який я задав",
        "Name, A to Z": "Назвою, від А до Я",
        "Newest first": "Спочатку найновіші",
        "Most questions first": "Спочатку з найбільшою кількістю питань",
        "Least practiced first": "Спочатку найменш опрацьовані",
        "Import question bank PDF…": "Імпортувати PDF з банку питань…",
        "or drag PDFs into this window": "або перетягніть PDF у це вікно",
        "Rename…": "Перейменувати…",
        "Add another PDF to this set…": "Додати ще один PDF до цього набору…",
        "Reset my progress": "Скинути мій прогрес",
        "Delete": "Видалити",
        "Cancel": "Скасувати",
        "Save": "Зберегти",
        "Name": "Назва",
        "questions": "питань",
        "seen": "переглянуто",

        "Practice": "Практика",
        "Statistics": "Статистика",
        "What to practice": "Що практикувати",
        "Sections": "Розділи",
        "Reading and Writing": "Читання та письмо",
        "Math": "Математика",
        "Which questions": "Які питання",
        "How many questions": "Скільки питань",
        "Order": "Порядок",
        "Assessment": "Іспит",
        "Difficulty": "Складність",
        "Domain": "Домен",
        "Skill": "Навичка",
        "Narrow it down": "Звузити вибір",
        "everything": "усе",
        "All": "Усі",
        "Custom": "Свій",
        "Start practice": "Почати практику",
        "Begin full test": "Почати повний тест",
        "Name this sitting": "Назвати цю сесію",
        "Study plans": "Плани навчання",
        "Save these settings": "Зберегти ці налаштування",
        "Plan": "План",
        "Close": "Закрити",
        "Color %d": "Колір %d",
        "Today": "Сьогодні",

        "Continue where I left off": "Продовжити з того місця, де я зупинився",
        "Only questions I have never seen": "Лише питання, яких я ще не бачив",
        "Due for review": "Час повторити",
        "Drill my weakest skills": "Тренувати найслабші навички",
        "Review my missed questions": "Переглянути питання, у яких я помилився",
        "Questions I set aside": "Питання, які я відклав",
        "Everything in the bank": "Усе з банку питань",
        "Unseen questions first, then ones you got wrong.":
            "Спочатку нові питання, потім ті, у яких ви помилилися.",
        "Completely fresh ones, skipping anything you set aside.":
            "Лише зовсім нові, без тих, які ви відклали.",
        "Drawn from the skills you are scoring lowest on, worst first.":
            "З навичок, за якими у вас найнижчі результати, починаючи з найслабшої.",
        "Only questions you have answered incorrectly before.":
            "Лише питання, на які ви раніше відповіли неправильно.",
        "The ones you kept back to look at later.":
            "Ті, які ви відклали, щоб переглянути пізніше.",
        "Draw from the whole bank, seen or not.":
            "Брати з усього банку, переглянуті чи ні.",

        "Sit a full test": "Скласти повний тест",
        "Start a new practice?": "Почати нову практику?",
        "You have a test in progress — %@. Starting a new one replaces it, and the answers in it are lost.":
            "У вас є незавершений тест — %@. Якщо почати новий, він замінить попередній, і відповіді в ньому буде втрачено.",
        "figures from your PDFs": "рисунки з ваших PDF",
        "copies of the PDFs you imported": "копії PDF, які ви імпортували",
        "Two things take nearly all of it: the figures drawn out of your PDFs, which are the questions themselves, and the copies of the PDFs you imported. Those copies can be deleted one at a time from the practice screen and every question stays.":
            "Майже все займають дві речі: рисунки, добуті з ваших PDF, — це і є самі запитання, — та копії PDF, які ви імпортували. Ці копії можна видаляти по одній на екрані практики, і всі запитання залишаться.",
        "Drawing the figures · %1$d of %2$d": "Малюємо рисунки · %1$d з %2$d",
        "with %@": "разом з %@",
        "Reading page %1$d of %2$d": "Читаємо сторінку %1$d з %2$d",
        "not while two of you are studying": "не тоді, коли ви вчитеся вдвох",
        "not enough questions": "недостатньо питань",
        "Adaptive second module": "Адаптивний другий модуль",
        "Mixed practice": "Змішана практика",
        "How many of each": "Скільки з кожного",
        "Mixed together": "Разом, упереміш",
        "the total is drawn from both sections": "загальна кількість береться з обох розділів",
        "Choose how many of each": "Обрати, скільки з кожного",
        "Mix them": "Перемішати",

        "Directions": "Інструкції",
        "Mark for Review": "Позначити для перегляду",
        "Set aside": "Відкласти",
        "Reference": "Довідка",
        "Highlights & Notes": "Виділення та нотатки",
        "More": "Ще",
        "Back": "Назад",
        "Next": "Далі",
        "Submit": "Здати",
        "Submit module": "Здати модуль",
        "Finish test": "Завершити тест",
        "Untimed": "Без часу",
        "Hide": "Сховати",
        "Show": "Показати",
        "THIS IS A PRACTICE TEST": "ЦЕ ТРЕНУВАЛЬНИЙ ТЕСТ",
        "Go to question": "Перейти до питання",
        "Answered": "Є відповідь",
        "Unanswered": "Без відповіді",
        "For review": "Для перегляду",
        "Enter your answer": "Введіть відповідь",
        "Highlight": "Виділити",
        "Add note": "Додати нотатку",
        "Save and leave": "Зберегти й вийти",
        "Submit section": "Здати розділ",
        "Quit without saving": "Вийти без збереження",
        "Keep working": "Продовжити",
        "Keep your place and come back to it later.":
            "Зберегти місце й повернутися пізніше.",
        "Finish now and see your results.":
            "Завершити зараз і побачити результати.",
        "Throw this sitting away.": "Скасувати цю сесію.",

        "BREAK": "ПЕРЕРВА",
        "Resume testing": "Продовжити тест",
        "The clock starts again when the break ends, whether you are back or not.":
            "Час піде знову після завершення перерви — незалежно від того, чи ви повернулися.",

        "Settings": "Налаштування",
        "About %@": "Про %@",
        "Settings…": "Налаштування…",
        "Appearance": "Вигляд",
        "Storage": "Зберігання",
        "About": "Про застосунок",
        "Done": "Готово",
        "Theme": "Тема",
        "Language": "Мова",
        "Match the system": "Як у системі",
        "Beige": "Бежева",
        "Navy": "Темно-синя",
        "Follow whatever macOS is set to.": "Використовувати налаштування macOS.",
        "Navy ink on beige paper.": "Темно-синій текст на бежевому тлі.",
        "Beige ink on navy paper.": "Бежевий текст на темно-синьому тлі.",
        "Motion": "Анімація",
        "Reduce motion in this app": "Зменшити анімацію в цьому застосунку",
        "Your daily target": "Ваша денна ціль",
        "Where everything is kept": "Де все зберігається",
        "Open this folder": "Відкрити цю теку",
        "What is in it": "Що всередині",
        "No question sets yet.": "Наборів питань ще немає.",
        "The small print": "Дрібний шрифт",

        "Choose a PDF…": "Обрати PDF…",
        "Everything stays on this Mac. No account, no network, no subscription.":
            "Усе залишається на цьому Mac. Без облікового запису, без мережі, без підписки.",

        "correct": "правильно",
        "Why": "Чому",
        "Correct": "Правильно",
        "Check answer": "Перевірити відповідь",

        "%1$@ · %2$@": "%1$@ · %2$@",
        "%1$@ · %2$d questions · %3$d min": "%1$@ · %2$d {запитання|запитання|запитань} · %3$d хв",
        "%1$d Reading and Writing and %2$d Math, in four timed modules with a %3$d-minute break — %4$d minutes of testing.":
            "%1$d «Читання та письмо» і %2$d «Математика» — чотири модулі на час, з %3$d-хвилинною перервою — %4$d {хвилина|хвилини|хвилин} тестування.",
        "%1$d of %2$d available": "%1$d з %2$d доступно",
        "%1$d questions · %2$d seen": "%1$d {запитання|запитання|запитань} · %2$d переглянуто",
        "%d question set(s) could not be read": "Не вдалося прочитати %d набір(-и) запитань",
        "%d questions": "%d запитань",
        "A large Math export can take a minute. The window stays usable while it reads.":
            "Великий експорт із Математики може тривати хвилину. Вікно залишається доступним, поки триває зчитування.",
        "A negative answer keeps its minus sign: −3/5 or −0.6.":
            "Від'ємна відповідь зберігає знак мінус: −3/5 або −0.6.",
        "A repeating decimal is right if you give enough of it: 2/3 can be entered as 2/3, .6666 or 0.667.":
            "Періодичний десятковий дріб зараховується як правильна відповідь, якщо ви вказали достатньо знаків: 2/3 можна ввести як 2/3, .6666 або 0.667.",
        "About this app, and United States Universities For Ukraine":
            "Про цей застосунок і United States Universities For Ukraine",
        "Accuracy over your last sittings": "Точність за останні спроби",
        "Admissions, scholarships and aid, visas and documents, grade converters, and a planning timeline — all free, in English and Ukrainian.":
            "Вступ, стипендії та фінансова допомога, візи й документи, конвертери оцінок і таймлайн підготовки — усе безкоштовно, англійською та українською.",
        "All Reading and Writing, then all Math, in file order.":
            "Спочатку все «Читання та письмо», потім уся «Математика» — у порядку файлу.",
        "And again in the evening if the streak is about to go":
            "І ще раз увечері, якщо серія ось-ось урветься",
        "Answer Eliminator — cross out choices you have ruled out":
            "Викреслювання відповідей — закреслюйте варіанти, які ви виключили",
        "Answer at least %d questions in a skill and it will be ranked here. Below that a percentage says more about luck than about you.":
            "Дайте відповідь щонайменше на %d {запитання|запитання|запитань} у навичці, і вона з'явиться в цьому рейтингу. До цього відсоток каже більше про удачу, ніж про вас.",
        "Drag to resize · double-click to fit":
            "Потягніть, щоб змінити розмір · подвійний клік — за вмістом",
        "Type any number of questions": "Введіть будь-яку кількість запитань",
        "Worst first": "Найгірші спершу",
        "Most answered": "Найбільше відповідей",
        "Least covered": "Найменше охоплено",
        "Slowest": "Найповільніші",
        "A–Z": "А–Я",
        "What these figures cover": "Що охоплюють ці цифри",
        "Section": "Розділ",
        "Both": "Обидва",
        "All domains": "Усі домени",
        "All skills": "Усі навички",
        "Show everything": "Показати все",
        "%d answer in this slice": "%d відповідь у цьому зрізі",
        "Nothing answered in this slice yet.": "У цьому зрізі ще немає відповідей.",
        "By section": "За розділом",
        "Show only this section": "Показати лише цей розділ",
        "The two sections are running at about the same accuracy.":
            "Обидва розділи йдуть приблизно з однаковою точністю.",
        "%1$@ is %2$d points behind %3$@ — that is where the marks are going.":
            "%1$@ відстає від %3$@ на %2$d {пункт|пункти|пунктів} — саме там втрачаються бали.",
        "Nothing answered in this slice yet":
            "У цьому зрізі ще немає відповідей",
        "Nothing has been answered here yet.":
            "Тут ще немає жодної відповіді.",
        "Practice %@":
            "Практикувати: %@",
        "You have not answered anything in %@ in this set yet. Widen it above, or practice some.":
            "У цьому наборі ви ще не відповідали нічого в розділі %@. Розширте вибір вище або попрактикуйтеся.",
        "By difficulty": "За складністю",
        "By domain": "За доменом",
        "Clear all filters": "Скинути всі фільтри",
        "Clear filters": "Скинути фільтри",
        "Clear statistics": "Очистити статистику",
        "Collapse all": "Згорнути все",
        "Customization": "Персоналізація",
        "Discard": "Відхилити",
        "Dismiss": "Закрити",
        "Do not type a comma, units, a percent sign, or a dollar sign.":
            "Не вводьте коми, одиниці виміру, знак відсотка чи знак долара.",
        "Type a mixed number such as 3½ as 7/2 or 3.5. Typed as 3 1/2, it reads as 31/2 and is marked wrong.":
            "Мішане число, наприклад 3½, вводьте як 7/2 або 3.5. Введене як 3 1/2, воно читається як 31/2 і зараховується як помилка.",
        "You can type up to 5 characters for a positive answer and 6 for a negative one; the minus sign counts.":
            "Можна ввести до 5 символів для додатної відповіді і до 6 для від'ємної; знак мінус теж рахується.",
        "Each module is timed on its own and cannot be reopened once handed in, the same as on the real test.":
            "Кожен модуль має власний таймер і не може бути відкритий повторно після здачі — так само, як на справжньому тесті.",
        "Each point is one sitting: answers separated by more than half an hour start a new one.":
            "Кожна точка — це одна спроба: якщо між відповідями минуло більше півгодини, починається нова.",
        "Each question is based on one or more passages, which may include a table or a graph. Read the passage and the question, then choose the best answer.":
            "Кожне запитання ґрунтується на одному або кількох текстах, які можуть містити таблицю або графік. Прочитайте текст і запитання, а потім оберіть найкращу відповідь.",
        "Easier form": "Легша форма",
        "Empty the list": "Очистити список",
        "Enter a fraction as 3/4, or its decimal as 0.75 — either counts. You do not have to reduce it.":
            "Введіть дріб як 3/4 або його десятковий еквівалент як 0.75 — зараховується будь-який варіант. Скорочувати дріб не обов'язково.",
        "Every question has four choices and exactly one best answer.":
            "Кожне запитання має чотири варіанти відповіді й лише одну найкращу відповідь.",
        "Everything else is on our website": "Усе інше — на нашому сайті",
        "Everything you have highlighted or noted on this question":
            "Усе, що ви виділили або занотували до цього запитання",
        "Expand all": "Розгорнути все",
        "Export as PDF…": "Експортувати як PDF…",
        "Export missed questions as PDF…": "Експортувати пропущені запитання як PDF…",
        "Export the questions you want from the College Board's Question Bank and import the PDF here. It becomes a practice test you can sit as many times as you like.":
            "Експортуйте потрібні запитання з Question Bank College Board і імпортуйте PDF сюди. Це стане пробним тестом, який можна проходити скільки завгодно разів.",
        "Feels like the real test. You see all results after you submit.":
            "Відчувається як справжній тест. Усі результати ви побачите після завершення.",
        "Finish a practice section and this fills in: which skills you are strongest and weakest at, how you do by difficulty, and whether you are improving.":
            "Завершіть тренувальний розділ, і тут з'явиться інформація: у яких навичках ви найсильніші й найслабші, як ви справляєтеся із запитаннями різної складності та чи прогресуєте ви.",
        "Flag this question so you can come back to it":
            "Позначте це запитання, щоб повернутися до нього пізніше",
        "Follow a study plan": "Дотримуйтеся плану підготовки",
        "Forget this plan": "Забути цей план",
        "Formulas and figures provided on the Math section":
            "Формули та рисунки, надані в розділі «Математика»",
        "Grade at the end": "Оцінювати наприкінці",
        "Grade each question": "Оцінювати кожне запитання",
        "Harder form": "Складніша форма",
        "Highlight the selected text": "Виділити позначений текст",
        "How much of the bank you have covered": "Яку частину банку питань ви опрацювали",
        "How the sets are ordered — currently %@": "Як упорядковано набори — зараз %@",
        "How to practice": "Як тренуватися",
        "Image missing": "Зображення відсутнє",
        "Import a PDF exported from the College Board Question Bank — SAT or PSAT.":
            "Імпортуйте PDF, експортований із College Board Question Bank — SAT або PSAT.",
        "It was imported before the reader learned to keep tables, underlined text, and hyphens. Reading the stored PDFs again fixes those. Your progress, notes, and set-aside list are kept.":
            "Його імпортували до того, як зчитувач навчився зберігати таблиці, підкреслений текст і дефіси. Повторне зчитування збережених PDF виправляє це. Ваш прогрес, нотатки та список відкладених питань зберігаються.",
        "Keep the order the questions came in.": "Зберегти порядок, у якому надійшли питання.",
        "Keep this question to look at again at the end of your study time":
            "Відкласти це питання, щоб переглянути його наприкінці заняття",
        "Larger text": "Більший текст",
        "This question already fills the window — make the window wider to go larger":
            "Це питання вже заповнює вікно — розширте вікно, щоб збільшити далі",
        "Last updated: %@.": "Востаннє оновлено: %@.",
        "Mixed": "Змішаний",
        "Morning drill": "Ранкове тренування",
        "Next: %@": "Далі: %@",
        "No PDFs stored for this set yet.": "Для цього набору ще не збережено жодного PDF.",
        "No account, no network, no subscription, no tracking. Your questions, answers and progress stay in a folder you can open, copy and delete yourself.":
            "Без акаунтів, без мережі, без підписки, без стеження. Ваші питання, відповіді та прогрес зберігаються в папці, яку ви самі можете відкрити, скопіювати чи видалити.",
        "No question sets yet": "Ще немає наборів питань",
        "Not enough attempts to judge": "Замало спроб, щоб оцінити",
        "Nothing leaves your computer": "Нічого не залишає ваш комп'ютер",
        "Nothing marked on this question yet": "Це питання ще нічим не позначено",
        "Nothing to show yet": "Поки що нічого показати",
        "Once you have answered a few more questions this shows which kinds take you longest.":
            "Коли ви дасте відповідь ще на кілька питань, тут буде видно, які типи забирають у вас найбільше часу.",
        "One section after the other": "Один розділ за іншим",
        "Opens in your browser": "Відкривається у браузері",
        "PDF order": "Порядок PDF",
        "Pick at least one day, or the plan is a plan to do nothing.":
            "Оберіть хоча б один день, інакше цей план — план нічого не робити.",
        "Practice that knows what you missed": "Практика, яка знає, що ви пропустили",
        "Practice these": "Тренуйте це",
        "Practice these again": "Тренуйте це знову",
        "Question %1$d of %2$d · %3$d answered": "Питання %1$d із %2$d · дано %3$d {відповідь|відповіді|відповідей}",
        "Question %d": "Питання %d",
        "Questions a day": "Питань на день",
        "Questions you get wrong come back, spaced out over days. The statistics say which skills are costing you marks, and you can drill exactly those.":
            "Питання, на які ви відповіли неправильно, повертаються з інтервалами протягом кількох днів. Статистика показує, які навички коштують вам балів, і ви можете тренувати саме їх.",
        "Reading and Writing and Math can live in one set, and so can SAT and PSAT — you choose what to draw from above.":
            "Читання та письмо і Математика можуть бути в одному наборі, так само як SAT і PSAT — ви самі обираєте, з чого брати питання.",
        "Reading and Writing first, then Math, but shuffled within each.":
            "Спочатку Читання та письмо, потім Математика, але в перемішаному порядку всередині кожного розділу.",
        "Reading this set again with the current reader…":
            "Повторне зчитування цього набору поточним зчитувачем…",
        "Reading your question bank": "Зчитування вашого банку питань",
        "Reading…": "Зчитування…",
        "Reference — the formulas and figures the test provides — is in the toolbar and can be opened at any time.":
            "Довідка — формули та фігури, надані тестом, — розміщена на панелі інструментів, і її можна відкрити будь-коли.",
        "Remind me": "Нагадати мені",
        "Reminders need the built app rather than a development run.":
            "Для нагадувань потрібна зібрана програма, а не режим розробки.",
        "Remove": "Видалити",
        "Remove all": "Видалити все",
        "Remove highlight": "Прибрати виділення",
        "Resume": "Продовжити",
        "Save a copy…": "Зберегти копію…",
        "Save the settings you use most and they come back in one click.":
            "Збережіть налаштування, якими ви користуєтеся найчастіше, і вони повертатимуться одним кліком.",
        "Section complete": "Секцію завершено",
        "See results": "Переглянути результати",
        "Select words in a passage, or in Math text without formulas, to highlight them, and add a note if you want one.":
            "Виділіть слова в тексті або в тексті з математики без формул, щоб позначити їх кольором, і додайте нотатку, якщо потрібно.",
        "Set aside for later": "Відкласти на потім",
        "Set aside while you were practicing, waiting for you to come back to them.":
            "Відкладені під час практики — чекають, поки ви до них повернетесь.",
        "Shows the answer and explanation right after you answer.":
            "Показує відповідь і пояснення одразу після того, як ви відповісте.",
        "Shuffle both sections together.": "Перемішати обидві секції разом.",
        "Shuffled inside each section": "Перемішані в межах кожної секції",
        "Smaller text": "Менший текст",
        "Sorting never overwrites the order you arranged by hand — switch back and it returns.":
            "Сортування ніколи не перезаписує порядок, який ви впорядкували вручну, — перемкніться назад, і він повернеться.",
        "Spaced practice: questions come back a day after you get one wrong, and at widening gaps while you keep getting it right.":
            "Інтервальна практика: питання повертаються через день після того, як ви їх отримали неправильно, і з дедалі більшими проміжками, поки ви відповідаєте правильно.",
        "Special Right Triangles": "Особливі прямокутні трикутники",
        "Takes effect straight away. The test screen never animated anyway — a sitting should feel like the real thing.":
            "Діє одразу. Екран тесту й так ніколи не анімувався — сесія має відчуватися як справжній тест.",
        "The app fades cards in, counts figures up and slides marks between choices. Turn it off if you would rather it just appeared.":
            "Застосунок плавно показує картки, відлічує цифри та переміщує позначки між варіантами. Вимкніть це, якщо хочете, щоб усе просто з'являлося одразу.",
        "The clock is showing again so you can pace the rest of the section.":
            "Годинник знову показано, щоб ви могли розрахувати час на решту секції.",
        "The imported questions and your progress for this set will be removed. The original PDF is not touched.":
            "Імпортовані питання та ваш прогрес для цього набору буде видалено. Оригінальний PDF залишиться недоторканим.",
        "The organization's two papers. Whichever you pick, the test screen stays white — the real one is, and every figure in your PDFs is drawn on white. Stealth Mode below is the one thing that changes that.":
            "Два варіанти паперу організації. Який би ви не обрали, екран тесту залишається білим — справжній тест саме такий, і всі рисунки у ваших PDF намальовані на білому тлі. Нічний режим нижче — єдине, що це змінює.",
        "The questions stay in the bank and your progress is untouched; only the list of ones you kept back is cleared.":
            "Питання залишаються в банку, а ваш прогрес не змінюється — очищується лише список відкладених питань.",
        "The real thing's shape": "Форма справжнього тесту",
        "The ring on the practice screen, and the days you have set aside, are part of your study plan — press Plan beside the ring to change them. They are kept there rather than here because they are something you look at while deciding what to practice.":
            "Кільце на екрані практики та дні, які ви відклали для занять, — частина вашого плану навчання. Натисніть «План» біля кільця, щоб їх змінити. Вони зберігаються там, а не тут, бо це те, на що ви дивитесь, вирішуючи, що практикувати.",
        "The routing cut is %d%% of module 1. The College Board does not publish theirs, so this one is ours.":
            "Поріг маршрутизації становить %d%% модуля 1. College Board не публікує свій, тож цей — наш.",
        "The screen, the timing and the controls follow the digital test, so the format costs you nothing on the day. Sit a single module or the whole test, with the break.":
            "Екран, хронометраж і елементи керування відповідають цифровому тесту, тож формат не стане для вас несподіванкою в день іспиту. Пройдіть один модуль або весь тест, із перервою.",
        "The timer has run out. Your answers have been kept.":
            "Час вийшов. Ваші відповіді збережено.",
        "These settings are saved under that name and can be applied to any question set in one click.":
            "Ці налаштування зберігаються під цією назвою і можуть застосовуватися до будь-якого набору питань в один клік.",
        "This app is one part of that, and it is free. The rest is on our website: guides to admissions, scholarships and financial aid, visas and documents, grade and score converters, and planning timelines.":
            "Цей застосунок — лише частина цієї роботи, і він безкоштовний. Решта — на нашому сайті: гайди про вступ, стипендії та фінансову допомогу, візи й документи, конвертери оцінок і балів, а також таймлайни планування.",
        "This clears the record of every answer you have given, so the charts start over. Which questions you have seen, your set-aside list, and your notes are all kept.":
            "Це очищує запис усіх ваших відповідей, тож графіки починаються заново. Які питання ви вже бачили, ваш список відкладених питань і ваші нотатки — все це зберігається.",
        "This set can be read again": "Цей набір можна перечитати",
        "This week against your plan": "Цей тиждень порівняно з вашим планом",
        "United States Universities For Ukraine is an independent, non-profit educational initiative. We help Ukrainian students and their families understand how studying in the United States actually works — what to prepare, when, and what it costs.":
            "United States Universities For Ukraine — незалежна некомерційна освітня ініціатива. Ми допомагаємо українським студентам та їхнім родинам зрозуміти, як насправді відбувається навчання у США: що готувати, коли і скільки це коштує.",
        "Unless a question says otherwise: all variables and expressions stand for real numbers, figures are drawn to scale, every figure lies in a plane, and the domain of a function is every real number for which the function is real.":
            "Якщо в запитанні не вказано інше: усі змінні та вирази позначають дійсні числа, фігури зображено в масштабі, кожна фігура лежить у площині, а областю визначення функції є всі дійсні числа, для яких функція набуває дійсного значення.",
        "Use a timer": "Використовувати таймер",
        "Version %@": "Версія %@",
        "What this app does": "Що робить цей застосунок",
        "What to call this sitting at the top of the test screen":
            "Як назвати цю сесію вгорі екрана тесту",
        "Where you are losing marks": "Де ви втрачаєте бали",
        "Which days you practice, how much, and when to be reminded":
            "У які дні ви практикуєтесь, скільки і коли отримувати нагадування",
        "Who we are": "Хто ми",
        "You can highlight text in one of four colors and attach a note to it. Highlighting works on Reading and Writing passages and on Math text that contains no formulas. Highlights are kept with the question.":
            "Ви можете виділити текст одним із чотирьох кольорів і додати до нього примітку. Виділення працює в текстах розділу «Читання та письмо» і в тексті з математики, що не містить формул. Виділення зберігаються разом із запитанням.",
        "You have a test in progress": "У вас є незавершений тест",
        "Section %1$d, Module %2$d: %3$@": "Розділ %1$d, Модуль %2$d: %3$@",
        "Student": "Учень",
        "These articles cover the basics of each skill and nothing more. They are a place to start, not a course, and they will not on their own get you any particular score. Real preparation means working through questions, and reading properly about the topics you find hard — this is only meant to help you begin.": "Ці статті охоплюють основи кожної навички й не більше. Це місце, з якого можна почати, а не курс, і самі по собі вони не дадуть вам жодного конкретного балу. Справжня підготовка — це розв'язувати запитання й уважно читати про теми, які даються важко; це лише допомога на початку.",
        "Four languages, the way the website does it. Anything not yet translated stays in English rather than showing a gap.": "Чотири мови, як і на сайті. Усе, що ще не перекладено, залишається англійською, а не стає порожнім місцем.",
        "What the app shows": "Що показує застосунок",
        "The sidebar and the practice screen carry the same signposts on your first day and your two-hundredth. Turn off the ones you have stopped needing.": "Бічна панель і екран практики містять ті самі підказки і першого дня, і двохсотого. Вимкніть ті, які вам більше не потрібні.",
        "Learn in the sidebar": "Навчання в бічній панелі",
        "What you study": "Що ви вивчаєте",
        "What this app is for, for you": "Для чого цей застосунок саме вам",
        "Turn off the parts you are not using and they leave the sidebar entirely. Nothing is deleted: your sets, your progress, your decks and your notes are all still on this computer, and turning a part back on brings it back exactly as it was.": "Вимкніть те, чим не користуєтеся, і воно повністю зникне з бічної панелі. Нічого не видаляється: ваші набори, ваш прогрес, ваші колоди й ваші примітки залишаються на цьому комп'ютері, і якщо ввімкнути частину знову, вона повернеться точно такою, якою була.",
        "SAT practice": "Підготовка до SAT",
        "Your question sets, the practice screen, the statistics and the Import button. Off, the library goes with them — for a student using this only for vocabulary.": "Ваші набори запитань, екран практики, статистика й кнопка імпорту. Якщо вимкнути, бібліотека зникне разом з ними — для учня, який користується цим лише для лексики.",
        "Your decks, the cards in them and the vocabulary test. Off, the Flashcards section goes — for a student who came here for the questions.": "Ваші колоди, картки в них і тест з лексики. Якщо вимкнути, розділ «Картки» зникне — для учня, який прийшов сюди за запитаннями.",
        "Short explanations of what each skill actually is. Articles are still reachable from a question you got wrong and from the statistics screen.": "Короткі пояснення того, чим насправді є кожна навичка. Статті все одно доступні із запитання, у якому ви помилилися, і з екрана статистики.",
        "Both are off, so there is nothing to study. The sidebar says as much and points back here.": "Обидва вимкнені, тож вивчати нічого. Бічна панель так і каже та відсилає назад сюди.",
        "Nothing to study yet": "Поки що нічого вивчати",
        "Please choose what you want to study in Settings — SAT practice, flashcards, or both. Nothing of yours has been deleted.": "Будь ласка, виберіть у налаштуваннях, що ви хочете вивчати — підготовку до SAT, картки або і те, і те. Нічого вашого не видалено.",
        "Open Settings": "Відкрити налаштування",
        "Pick a deck on the left to study your words, or make a new one. SAT practice is turned off; Settings will bring it back whenever you want it.": "Виберіть колоду ліворуч, щоб вивчати слова, або створіть нову. Підготовку до SAT вимкнено; налаштування повернуть її, коли захочете.",
        "The Import button": "Кнопка імпорту",
        "Dragging a PDF onto the window still works, and the button comes back on its own if a question set is ever needed.": "Перетягування PDF у вікно працює й далі, а кнопка повертається сама, якщо набір запитань стане потрібен.",
        "Streaks": "Серії",
        "A run of days can be the thing that keeps you going or the thing you are afraid to break. Either one can be turned off on its own. The days themselves are still recorded, so turning a streak back on loses nothing.": "Серія днів може бути тим, що тримає вас, або тим, що страшно обірвати. Кожну можна вимкнути окремо. Самі дні все одно записуються, тож повернути серію можна без втрат.",
        "The streak on the practice screen": "Серія на екрані практики",
        "Counted against the days in your study plan, where a planned rest day is skipped rather than failed.": "Рахується за днями вашого плану навчання, де запланований день відпочинку пропускається, а не зараховується як провал.",
        "The streak on a flashcard deck": "Серія в колоді карток",
        "Counted on the days you finish the words you were dealt.": "Рахується за днями, коли ви завершуєте видані слова.",
        "Days you have practiced": "Дні, коли ви практикувались",
        "days finished": "днів завершено",
        "of this period": "цього періоду",
        "Back to the library": "Назад до бібліотеки",
        "Turning up": "Присутність",
        "Week": "Тиждень",
        "Month": "Місяць",
        "3 months": "3 місяці",
        "Year": "Рік",
        "For a parent": "Для батьків",
        "A plain-language page about how this is going, in whichever language you have the app set to. Print it or send it.": "Сторінка простою мовою про те, як усе просувається, тією мовою, яку ви обрали в застосунку. Роздрукуйте її або надішліть.",
        "Save as a page…": "Зберегти як сторінку…",
        "Saved %@": "Збережено %@",
        "One page, in the language the app is set to. It holds no personal information beyond the name shown on it.": "Одна сторінка мовою, яку обрано в застосунку. Вона не містить жодної особистої інформації, крім імені на ній.",
        "Practice summary — %@": "Підсумок практики — %@",
        "The last %1$d days · %2$@": "Останні %1$d {день|дні|днів} · %2$@",
        "There is no practice recorded in this period yet.": "За цей період практики ще не записано.",
        "answered correctly": "правильних відповідей",
        "%1$@ practiced on %2$d of the last %3$d days and answered %4$d questions.": "%1$@ — практика у %2$d з останніх %3$d {дня|днів|днів}; відповідей: %4$d.",
        "Going well: %@.": "Добре йде: %@.",
        "Finding harder: %@.": "Складніше дається: %@.",
        "These are the topics where help would make the most difference right now.": "Саме в цих темах допомога зараз дала б найбільше.",
        "There is not yet enough practice in any one topic to say which are going well and which are not.": "Поки що замало практики в будь-якій окремій темі, щоб сказати, які йдуть добре, а які ні.",
        "These figures come from practice in this app only. They are not a predicted SAT score, and this app cannot produce one — a question bank is not a scored test.": "Ці цифри стосуються лише практики в цьому застосунку. Це не прогнозований бал SAT, і цей застосунок не може його дати — банк запитань не є оціненим тестом.",
        "Nothing here is compared with other students. Everything stays on this computer.": "Нічого тут не порівнюється з іншими учнями. Усе залишається на цьому комп'ютері.",
        "Learn": "Навчання",
        "How each skill works": "Як працює кожна навичка",
        "Nothing matches that.": "Нічого не знайдено.",
        "Read about %@": "Прочитати про: %@",
        "Search the articles": "Пошук у статтях",
        "Short explanations of what each skill is actually about, written for a student who wants the idea rather than another question. They work offline like everything else here.": "Короткі пояснення того, про що насправді кожна навичка, для учня, якому потрібна ідея, а не ще одне запитання. Вони працюють офлайн, як і все тут.",
        "Correct:": "Правильна:",
        "Incorrect": "Неправильно",
        "Remove these from set aside": "Прибрати їх із відкладених",
        "Set aside all I got wrong": "Відкласти всі, у яких я помилився",
        "Your answer:": "Ваша відповідь:",
        "blank": "порожньо",
        "Sunday initial": "Н",
        "Monday initial": "П",
        "Tuesday initial": "В",
        "Wednesday initial": "С",
        "Thursday initial": "Ч",
        "Friday initial": "П",
        "Saturday initial": "С",
        "No plan — every day counts": "Плану немає — рахується кожен день",
        "No plan — %d a day, every day": "Плану немає — %d на день, щодня",
        "“%@” is locked with a password or encryption, so this app cannot read it. Export the questions again from the College Board Question Bank and import the new file.":
            "«%@» захищено паролем або шифруванням, тому застосунок не може його прочитати. Експортуйте запитання ще раз із College Board Question Bank та імпортуйте новий файл.",
        "%d a day, every day": "%d на день, щодня",
        "%1$d a day on %2$@": "%1$d на день: %2$@",
        "%1$d days in a row · %2$d to go today": "%1$d {день|дні|днів} поспіль · сьогодні {2:лишилось|лишились|лишилось} %2$d",
        "%d-day streak held · nothing planned today": "Серію з %d {дня|днів|днів} збережено · сьогодні нічого не заплановано",
        "First day of a new streak": "Перший день нової серії",
        "Nothing planned today": "На сьогодні нічого не заплановано",
        "Rest day": "День відпочинку",
        "Today's plan is done": "Сьогоднішній план виконано",
        "none": "немає",
        "A student using a library computer one day and a laptop the next should not have to start again. Export this student to a small file — it fits in an email — and import it on the other computer. A sitting in progress is not carried: it belongs to the computer it was begun on.": "Учень, який сьогодні працює за комп'ютером у бібліотеці, а завтра за ноутбуком, не має починати спочатку. Експортуйте цього учня в невеликий файл — він поміщається в лист — і імпортуйте на іншому комп'ютері. Незавершений сеанс не переноситься: він належить комп'ютеру, на якому його почали.",
        "Import a question bank to begin.": "Імпортуйте банк питань, щоб почати.",
        "Importing": "Імпортування",
        "In the College Board Question Bank — SAT or PSAT — pick the questions you want and choose Export. Import that PDF here and it becomes a practice test you can take as many times as you like.": "У банку питань College Board — SAT або PSAT — виберіть потрібні запитання й натисніть Export. Імпортуйте цей PDF сюди, і він стане практичним тестом, який можна проходити скільки завгодно разів.",
        "Read again": "Прочитати знову",
        "Reading the stored PDFs": "Читання збережених PDF",
        "Reminders here arrive while the app is open. Leave it running in the background and it will nudge you at the time you set.": "Нагадування тут надходять, поки застосунок відкритий. Залиште його працювати у фоні — і він нагадає вам у встановлений час.",
        "Study plan": "План навчання",
        "and again if the streak is about to go": "і ще раз, якщо серія ось-ось обірветься",
        "Export this student…": "Експортувати цього учня…",
        "Import a student file…": "Імпортувати файл учня…",
        "An exported student holds progress, statistics, highlights, notes, flashcard decks and study plans — everything except the question sets themselves, which stay as your own PDFs. A sitting in progress is not carried: it belongs to the computer it was begun on.": "Експортований учень містить прогрес, статистику, виділення, примітки, колоди карток і плани навчання — усе, крім самих наборів запитань, які залишаються вашими PDF-файлами. Незавершений сеанс не переноситься: він належить комп'ютеру, на якому його почали.",
        "Imported": "Імпортовано",
        "Nothing in that file matched anything here.": "Ніщо в цьому файлі не збіглося з тим, що є тут.",
        "Copy this onto a USB stick or email it to yourself, then import it on the other computer.": "Скопіюйте це на флешку або надішліть собі поштою, а потім імпортуйте на іншому комп'ютері.",
        "Exported %1$@ · %2$d KB": "Експортовано %1$@ · %2$d КБ",
        "Import %@": "Імпортувати %@",
        "a student": "учня",
        "Add to this student": "Додати до цього учня",
        "Bring in as a new student": "Внести як нового учня",
        "Where both computers have a record of the same question, the one with more attempts on it is kept. Importing the same file twice changes nothing.": "Якщо на обох комп'ютерах є запис про те саме запитання, зберігається той, у якому більше спроб. Повторний імпорт того самого файлу нічого не змінює.",
        "Import": "Імпортувати",
        "%1$d records": "записів: %1$d",
        "You have not imported this set here yet — its progress will be kept until you do.": "Ви ще не імпортували цей набір сюди — його прогрес зберігатиметься, доки ви це зробите.",
        "The same set as your “%@”": "Той самий набір, що і ваш «%@»",
        "Matched to your “%@” by name": "Зіставлено з вашим «%@» за назвою",
        "Matched to your “%1$@” — %2$d questions in common": "Зіставлено з вашим «%1$@» — спільних запитань: %2$d",
        "Moving between computers": "Перенесення між комп'ютерами",
        "A student using a library computer one day and a laptop the next should not have to start again. Export this student to a small file — it fits in an email — and import it on the other computer.": "Учень, який сьогодні працює за комп'ютером у бібліотеці, а завтра за ноутбуком, не має починати спочатку. Експортуйте цього учня в невеликий файл — він поміщається в лист — і імпортуйте на іншому комп'ютері.",
        "The student file could not be written.": "Не вдалося записати файл учня.",
        "That file could not be opened.": "Не вдалося відкрити цей файл.",
        "That is not a student file exported from this app.": "Це не файл учня, експортований із цього застосунку.",
        "Manage students…": "Керувати учнями…",
        "Switch student": "Змінити учня",
        "Delete %@?": "Видалити %@?",
        "Their progress, notes and flashcard decks are deleted. The question sets stay — they are shared with everyone on this computer.": "Їхній прогрес, примітки та колоди карток буде видалено. Набори запитань залишаться — вони спільні для всіх на цьому комп'ютері.",
        "Open now": "Зараз відкрито",
        "Open this student": "Відкрити цього учня",
        "Delete…": "Видалити…",
        "Add another student": "Додати ще одного учня",
        "Students on this computer": "Учні на цьому комп'ютері",
        "Students": "Учні",
        "Each student keeps their own progress, statistics, notes and flashcard decks. Question sets are shared, so a set only has to be imported once. Profiles are not password-protected — anyone using this computer can open any of them.": "Кожен учень має власний прогрес, статистику, примітки та колоди карток. Набори запитань спільні, тож набір достатньо імпортувати один раз. Профілі не захищені паролем — будь-хто за цим комп'ютером може відкрити будь-який із них.",
        "Profiles are not password-protected — anyone using this computer can open any of them. They exist so two students do not overwrite each other's work, not to keep it private.": "Профілі не захищені паролем — будь-хто за цим комп'ютером може відкрити будь-який із них. Вони існують, щоб двоє учнів не стирали роботу одне одного, а не щоб зберігати її в таємниці.",
        "Many families share one computer. Each student here keeps their own progress, statistics, notes and flashcard decks, and their own language and theme. Question sets are shared, so a set only has to be imported once — and it is the part that takes the disk space.": "Багато сімей користуються одним комп'ютером. Кожен учень тут має власний прогрес, статистику, примітки й колоди карток, а також власну мову та тему. Набори запитань спільні, тож набір достатньо імпортувати один раз — і саме він займає місце на диску.",
        "Module 1: %@": "Модуль 1: %@",
        "%@ practice": "Практика: %@",
        "%1$d Reading and Writing · %2$d Math": "%1$d з читання та письма · %2$d з математики",
        "untimed": "без обмеження часу",
        "under a minute left": "лишилось менше хвилини",
        "left off today": "зупинились сьогодні",
        "left off yesterday": "зупинились учора",
        "You may use a calculator on any question. This app does not provide one, so use whatever you will have on test day.":
            "Ви можете користуватися калькулятором для будь-якого запитання. Цей застосунок його не надає, тож використовуйте той, який буде у вас у день тесту.",
        "Your files are still on disk. Re-importing the original PDF will rebuild the set.":
            "Ваші файли досі на диску. Повторний імпорт оригінального PDF відновить набір.",
        "Your own question bank": "Власний банк питань",
        "Your place is saved, so you can pick this test up later from the home screen.":
            "Ваше місце збережено, тож ви можете продовжити цей тест пізніше з головного екрана.",
        "macOS is not allowing notifications for this app. System Settings › Notifications can turn them back on.":
            "macOS не дозволяє сповіщення для цього застосунку. Увімкнути їх знову можна в «Системних налаштуваннях» › «Сповіщення».",
        "macOS is set to Reduce Motion, so the app is already still whatever this is set to.":
            "У macOS увімкнено «Зменшення руху», тож застосунок уже статичний незалежно від цього налаштування.",
        "of %d": "з %d",
        "then a %d min break": "потім перерва %d хв",

        "Some questions ask you to type the answer rather than choose one. See \"Typing an answer\" below.":
            "Деякі питання просять ввести відповідь, а не обрати її. Див. «Як вводити відповідь» нижче.",
        "The real test allows 32 minutes for 27 Reading and Writing questions (%1$@ each) and 35 for 22 Math (%2$@ each).":
            "На справжньому тесті дають 32 хвилини на 27 питань з читання та письма (%1$@ на кожне) і 35 на 22 з математики (%2$@ на кожне).",

        "Answer %d questions to start a streak":
            "Дайте відповідь на %d питань, щоб почати серію",

        "Flashcards": "Картки",
        "New deck": "Нова колода",
        "Make a deck of vocabulary": "Створити колоду слів",
        "Rename deck": "Перейменувати колоду",
        "Rename student": "Перейменувати учня",
        "Student's name": "Ім'я учня",
        "Delete this deck?": "Видалити цю колоду?",
        "The cards in it are removed. Your question sets are not touched.":
            "Картки з неї буде видалено. Ваші набори питань залишаться недоторканими.",
        "Vocabulary": "Словник",
        "Double-click to rename this deck":
            "Двічі клацніть, щоб перейменувати колоду",
        "%d starred": "%d із зірочкою",
        "%d without a definition": "%d без визначення",
        "Test": "Тест",
        "Cards": "Список карток",
        "This deck is empty": "Ця колода порожня",
        "Take the words out of a question set you have already imported, or type "
            + "your own in. The Words-in-Context questions carry their own definitions, "
            + "so most words arrive with one already written.":
            "Візьміть слова з набору питань, який ви вже імпортували, або впишіть "
            + "свої. Питання на значення слова в контексті містять власні "
            + "визначення, тож більшість слів одразу приходить із поясненням.",
        "Take words from a question set…": "Взяти слова з набору питань…",
        "Import a question bank PDF first, or write your own cards on the Cards tab.":
            "Спочатку імпортуйте PDF з банку питань або впишіть свої картки на "
            + "вкладці «Список карток».",
        "Or write your own on the Cards tab.":
            "Або впишіть свої на вкладці «Список карток».",

        "Get a hint": "Підказка",
        "Star this word": "Позначити слово зірочкою",
        "Remove the star": "Зняти зірочку",
        "Click, or press space, to turn the card over":
            "Клацніть або натисніть пробіл, щоб перевернути картку",
        "Definition": "Визначення",
        "Word": "Слово",
        "No definition yet — open Cards to write one.":
            "Визначення ще немає — відкрийте «Список карток», щоб його вписати.",
        "All cards": "Усі картки",
        "Words I keep missing": "Слова, у яких я постійно помиляюсь",
        "Everything in this deck.": "Усе, що є в цій колоді.",
        "Show all cards": "Показати всі картки",
        "Stop autoplay": "Зупинити відтворення",
        "Play the cards, %d seconds a side":
            "Відтворювати картки, по %d с на сторону",
        "Shuffle the order": "Перемішати порядок",
        "Back to the deck's own order": "Повернути власний порядок колоди",
        "Fill the window": "На все вікно",
        "How long autoplay holds each side":
            "Скільки часу відтворення тримає кожну сторону",
        "Autoplay": "Відтворення",
        "A card is held on its front for this long, then on its back, "
            + "then the next one arrives.":
            "Стільки часу картка стоїть лицем, потім стільки ж зворотом, "
            + "а тоді приходить наступна.",

        "Search this deck": "Пошук у колоді",
        "Add a card": "Додати картку",
        "Add": "Додати",
        "What it means": "Що це означає",
        "A sentence using it": "Речення з цим словом",
        "Hint": "Підказка до слова",
        "Leave empty and half the definition is used":
            "Залиште порожнім — буде показано половину визначення",
        "Shown as: %@": "Буде показано: %@",
        "nothing yet — write a definition first":
            "поки нічого — спершу впишіть визначення",
        "Edit": "Редагувати",
        "Check that the folder is not read-only, or choose another one.": "Перевірте, що папка не лише для читання, або виберіть іншу.",
        "The disk is full. Free some space, or choose another place.": "Диск заповнений. Звільніть місце або виберіть інше місце.",
        "Check that the folder exists, or choose another one.": "Перевірте, що папка існує, або виберіть іншу.",
        "Edit card": "Редагувати картку",
        "Edit this card": "Редагувати цю картку",
        "Delete this card": "Видалити цю картку",
        "Delete this card?": "Видалити цю картку?",
        "\"%@\" will be removed from this deck.": "«%@» буде видалено з цієї колоди.",
        "No definition yet": "Визначення ще немає",
        "No card here matches that.": "Тут немає картки, яка б цьому відповідала.",
        "Nothing here yet. Type a word and what it means above, "
            + "or take a set of words out of a question bank.":
            "Поки що порожньо. Впишіть слово та його значення вгорі або візьміть "
            + "набір слів із банку питань.",
        "from %@": "з набору %@",
        "Right %1$d of %2$d in tests": "Правильно %1$d з %2$d у тестах",
        "Added \"%@\"": "Додано «%@»",
        "\"%@\" is already in this deck": "«%@» вже є в цій колоді",

        "Take words from a question set": "Взяти слова з набору питань",
        "The explanations in a College Board export define the words they test, "
            + "so the words come with their meanings already written. Anything the "
            + "reader could not define is still offered — you can write that one in.":
            "Пояснення в експорті College Board самі тлумачать слова, які "
            + "перевіряють, тож слова приходять уже зі значеннями. Те, чого "
            + "читач не зміг витлумачити, все одно пропонується — визначення "
            + "можна вписати самому.",
        "Find words": "Знайти слова",
        "Choose a question set and press Find words.":
            "Оберіть набір питань і натисніть «Знайти слова».",
        "Nothing found in that set. Words come from the "
            + "Words-in-Context questions, which the Math sets do not have.":
            "У цьому наборі нічого не знайдено. Слова беруться з питань на "
            + "значення слова в контексті, яких немає в наборах з математики.",
        "Only words with a definition": "Лише слова з визначенням",
        "Select all": "Обрати всі",
        "Select none": "Зняти вибір",
        "Add %d": "Додати %d",
        "No definition found — you can write one":
            "Визначення не знайдено — його можна вписати",
        "already here": "уже є",

        "What the four answers are": "Якими будуть чотири відповіді",
        "Definitions": "Визначеннями",
        "The words themselves": "Самими словами",
        "A mix of both": "Змішано",
        "You are shown the word and pick what it means.":
            "Вам показують слово, а ви обираєте, що воно означає.",
        "You are shown the meaning and pick the word.":
            "Вам показують значення, а ви обираєте слово.",
        "Some questions each way, decided per question.":
            "Частина питань так, частина навпаки — вирішується для кожного окремо.",
        "Which words": "Які слова",
        "A word needs a definition before it can be tested — a card with only a "
            + "word on it has no right answer to offer.":
            "Слово можна перевірити лише тоді, коли воно має визначення — картці "
            + "з самим лише словом нічого запропонувати як правильну відповідь.",
        "A test needs at least %d words with definitions. "
            + "This selection has %d.":
            "Для тесту потрібно щонайменше %d {слово|слова|слів} із визначеннями. "
            + "У цьому виборі їх %d.",
        "Start the test": "Почати тест",
        "What does this word mean?": "Що означає це слово?",
        "Which word means this?": "Яке слово це означає?",
        "Question %1$d of %2$d": "Питання %1$d з %2$d",
        "%d answered": "відповідей: %d",
        "Stop this test": "Зупинити тест",
        "%1$d of %2$d": "%1$d з %2$d",
        "%d%% right": "%d%% правильно",
        "Test again": "Пройти ще раз",
        "Test only what I missed": "Перевірити лише те, у чому помилився",
        "Star what I missed": "Позначити зірочкою те, у чому помилився",
        "Back to setup": "Назад до налаштувань",
        "Answer: %@": "Відповідь: %@",
        "You chose: %@": "Ви обрали: %@",
        "You left this one blank.": "Це питання залишилось без відповіді.",

        "Open the questions folder": "Відкрити теку з питаннями",
        "reading & writing": "читання та письмо",
        "math": "математика",
        "to review": "на повторення",
        "left blank": "без відповіді",
        "all": "усі",
        "min": "хв",
        "Days": "Дні",
        "Note": "Нотатка",
        "PDFs": "PDF-файли",
        "Open": "Відкрити",
        "Weakest": "Найслабше",
        "latest": "останні",
        "Pace": "Темп",
        "Clear": "Очистити",
        "Clear the statistics?": "Очистити статистику?",
        "Rename question set": "Перейменувати набір питань",
        "Delete this question set?": "Видалити цей набір питань?",
        "Delete this PDF?": "Видалити цей PDF?",
        "Name this plan": "Назвати цей план",
        "Empty": "Очистити",
        "Empty the set-aside list?": "Очистити список відкладених?",
        "No questions match these filters.": "Жодне питання не відповідає цим фільтрам.",
        "You have not set any questions aside yet.":
            "Ви ще не відклали жодного питання.",
        "Nothing to review — you have not got any of these wrong.":
            "Немає що повторювати — ви не помилились у жодному з них.",
        "You have seen every question that matches. Try another way of choosing.":
            "Ви вже бачили всі питання, що підходять. Спробуйте інший спосіб вибору.",
        "Not enough attempts yet to say which skills are weakest. "
            + "Answer at least %d questions in a skill and it can be ranked.":
            "Поки замало відповідей, щоб визначити найслабші вміння. Дайте "
            + "відповідь щонайменше на %d питань з одного вміння — і його "
            + "можна буде оцінити.",

        "Submit this section?": "Здати цей розділ?",
        "Submit this module?": "Здати цей модуль?",
        "Finish the test?": "Завершити тест?",
        "Finish": "Завершити",
        "Leave this test?": "Вийти з тесту?",
        "5 minutes remaining": "Залишилось 5 хвилин",
        "OK": "Гаразд",
        "Time\'s up": "Час вичерпано",
        "Undo": "Скасувати",
        "A full test needs %1$d Reading and Writing questions and %2$d Math. "
            + "You need %3$d more Reading and Writing and %4$d more Math.":
            "Для повного тесту потрібно %1$d {питання|питання|питань} з читання та письма і %2$d з "
            + "математики. Вам бракує ще %3$d з читання та письма і %4$d з математики.",
        "A full test needs %1$d Reading and Writing questions and %2$d Math. "
            + "You need %3$d more Reading and Writing.":
            "Для повного тесту потрібно %1$d {питання|питання|питань} з читання та письма і %2$d з "
            + "математики. Вам бракує ще %3$d з читання та письма.",
        "A full test needs %1$d Reading and Writing questions and %2$d Math. "
            + "You need %3$d more Math.":
            "Для повного тесту потрібно %1$d {питання|питання|питань} з читання та письма і %2$d з "
            + "математики. Вам бракує ще %3$d з математики.",

        "Got it": "Знаю",
        "Missed it": "Не знаю",
        "How did you do on %@?": "Як вам далося слово «%@»?",
        "Words I skipped past": "Слова, які я проминув",
        "Gone past twice or more without ever being turned over.":
            "Ті, повз які ви пройшли двічі або більше, жодного разу не перевернувши картку.",
        "You said Missed it, or picked the wrong answer in a test, "
            + "at least half the times you were asked.":
            "Ті, де ви натиснули «Не знаю» або обрали неправильну відповідь у "
            + "тесті щонайменше в половині випадків.",
        "Nothing is starred yet. Press the star on a card to keep it back "
            + "for later.":
            "Поки що нічого не позначено. Натисніть зірочку на картці, щоб "
            + "відкласти слово на потім.",
        "Nothing here yet. This fills up as you press Missed it on a card, "
            + "or get one wrong in a test.":
            "Поки що порожньо. Тут з’являться слова, де ви натиснете «Не знаю» "
            + "або помилитесь у тесті.",
        "Nothing here yet. This fills up with the words you go past "
            + "without turning over.":
            "Поки що порожньо. Тут з’являться слова, повз які ви пройшли, "
            + "не перевернувши картку.",
        "Nothing here yet.": "Поки що порожньо.",
        "right %1$d of %2$d": "правильно %1$d з %2$d",
        "turned over %d×": "перевернуто %d×",
        "skipped %d×": "проминуто %d×",

        "Smaller": "Менше",
        "Bigger": "Більше",
        "Back to the normal size": "Повернути звичайний розмір",
        "Turn with the animation": "Перевертати з анімацією",
        "Turn without the animation": "Перевертати без анімації",
        "Turn the card with an animation": "Перевертати картку з анімацією",
        "Also switchable from the corner of the card itself, which is where "
            + "you will want it mid-run.":
            "Перемикається також у кутку самої картки — саме там воно й "
            + "знадобиться посеред проходу колодою.",
        "How the cards behave when you are going through a deck.":
            "Як поводяться картки, поки ви йдете колодою.",
        "Count the words I skip past": "Рахувати слова, які я проминаю",
        "A word you go past without ever turning the card over goes into "
            + "\"Words I skipped past\". Nothing else can tell you which of a long "
            + "deck you have not really studied. Turn it off and the pile is hidden.":
            "Слово, повз яке ви пройшли, жодного разу не перевернувши "
            + "картку, потрапляє до «Слова, які я проминув». Ніщо інше не "
            + "підкаже, чого з довгої колоди ви насправді не вчили. Вимкніть — "
            + "і ця добірка сховається.",

        "Select this card": "Обрати цю картку",
        "%d selected": "обрано: %d",
        "Star them": "Позначити зірочкою",
        "Remove their stars": "Зняти зірочки",
        "Delete selected": "Видалити обрані",
        "Delete these cards?": "Видалити ці картки?",
        "Bold": "Жирний",
        "Italic": "Курсив",
        "Underline": "Підкреслений",
        "Select some text first": "Спершу виділіть текст",
        "How the card will read": "Як читатиметься картка",

        "Daily/Statistics": "Щодня / Статистика",
        "Today\'s words": "Сьогоднішні слова",
        "Today\'s few new words, and everything that has come back round.":
            "Кілька нових слів на сьогодні та все, що повернулось на повторення.",
        "A few words a day": "Кілька слів на день",
        "Ten new words a day, with everything that has come back round for "
            + "review, is about a quarter of an hour and adds up to more than "
            + "any amount of cramming the week before. Words you get wrong come "
            + "back tomorrow; words you keep getting right come back at "
            + "widening gaps.":
            "Десять нових слів на день разом із тим, що повернулось на "
            + "повторення, — це приблизно чверть години, і в сумі це дає більше, "
            + "ніж будь-яке зубріння за тиждень до тесту. Слова, у яких ви "
            + "помилились, повернуться завтра; ті, які ви стабільно знаєте, — "
            + "через дедалі довші проміжки.",
        "Start a daily set": "Почати щоденний набір",
        "Start today\'s words": "Почати сьогоднішні слова",
        "Go through them again": "Пройти ще раз",
        "Stop daily practice": "Припинити щоденну практику",
        "Today\'s words are done.": "Сьогоднішні слова опрацьовано.",
        "%1$d of %2$d words to go today.": "Сьогодні лишилось %1$d {слово|слова|слів} із %2$d.",
        "Nothing due today. Every word in this deck is resting.":
            "Сьогодні нічого повторювати. Усі слова цієї колоди відпочивають.",
        "Nothing stored to read again.":
            "Немає збережених файлів, щоб прочитати цей набір знову.",
        "Nothing to mark: every question was left blank.":
            "Немає що оцінювати: усі питання залишено без відповіді.",
        "Nothing due, and nothing new dealt yet.":
            "Немає що повторювати, і нових слів ще не роздано.",
        "Nothing due today, and no new words left in this deck. Add more "
            + "words, or practice the whole deck.":
            "Сьогодні нічого повторювати, і нових слів у цій колоді не лишилось. "
            + "Додайте ще слів або опрацюйте всю колоду.",
        "No new words today: %d are already waiting to be reviewed. They come "
            + "back as soon as you have cleared some — this is deliberate, and "
            + "it is the thing that keeps a daily set from turning into a "
            + "backlog nobody finishes.":
            "Сьогодні без нових слів: %d уже чекають на повторення. Вони "
            + "з’являться, щойно ви розберете частину — так задумано, і саме це "
            + "не дає щоденному набору перетворитись на завал, який ніхто не "
            + "розгрібає.",
        "Your run": "Ваша серія",
        "best run": "найкраща серія",
        "days done in all": "днів усього",
        "Finish today\'s words to start a run.":
            "Завершіть сьогоднішні слова, щоб розпочати серію.",
        "Today is done. Come back tomorrow — the gap is the part that does the work.":
            "На сьогодні все. Повертайтесь завтра — саме проміжок і робить роботу.",
        "How many new words a day": "Скільки нових слів на день",
        "Between %1$d and %2$d.": "Від %1$d до %2$d.",
        "Published advice for an adult learner lands between five and twenty "
            + "new words a day, and the reason is always the same: the limit is "
            + "not how many you can read but how many reviews they make for you "
            + "over the next month. Ten is a good place to start. Changing it "
            + "does not disturb words already dealt.":
            "Дослідження радять дорослому від п’яти до двадцяти нових слів на "
            + "день, і причина завжди та сама: межа — не в тому, скільки ви "
            + "здатні прочитати, а в тому, скільки повторень вони створять вам "
            + "на наступний місяць. Десять — гарний початок. Зміна цього числа "
            + "не чіпає вже роздані слова.",

        "A clock, if you want one": "Годинник, якщо хочете",
        "No clock": "Без годинника",
        "%d min": "%d хв",
        "or type a number": "або введіть число",
        "or type minutes": "або введіть хвилини",
        "%d of these words have a definition and can be asked about.":
            "%d із цих слів мають визначення, тож про них можна запитати.",
        "Vocabulary has no official pace — the SAT does not test words on their "
            + "own. A clock here is for making yourself answer from memory "
            + "instead of working it out.":
            "Для лексики немає офіційного темпу — SAT не перевіряє слова окремо. "
            + "Годинник тут для того, щоб змусити себе відповідати з пам’яті, а "
            + "не вираховувати.",
        "Time left in this test": "Часу лишилось у цьому тесті",

        "Sort": "Сортувати",
        "The order the cards are listed in": "Порядок, у якому перелічено картки",
        "The order they were added": "У порядку додавання",
        "Without a definition first": "Спершу без визначення",
        "A to Z": "Від А до Я",
        "Worst answered first": "Спершу найгірше засвоєні",
        "Skipped most first": "Спершу найчастіше проминуті",

        "Practice with cards": "Тренуватися з картками",
        "Back to the library — nothing is lost":
            "Назад до бібліотеки — нічого не втрачається",
        "Esc to leave": "Esc, щоб вийти",
        "Turn": "Переворот",

        "Star": "Зірочка",
        "Starred": "Із зірочкою",
        "Keep this word back to come to on its own, in Starred":
            "Відкласти це слово, щоб повернутись до нього окремо — у «Із зірочкою»",
        "Take the star off — it leaves the Starred list":
            "Зняти зірочку — слово залишить список «Із зірочкою»",
        "Words you starred to come back to on their own. Press the star "
            + "at the top of a card to put one here.":
            "Слова, які ви позначили зірочкою, щоб повернутись до них окремо. "
            + "Натисніть зірочку вгорі картки, щоб додати сюди слово.",

        "This deck": "Ця колода",
        "words": "слів",
        "known": "засвоєно",
        "still learning": "ще вчиться",
        "not met yet": "ще не зустрічались",
        "answered right": "правильних відповідей",
        "due now": "на повторення зараз",
        "due this week": "на повторення цього тижня",
        "starred": "із зірочкою",
        "no definition": "без визначення",
        "%1$d of the %2$d words with a definition have been answered right "
            + "four times running, which is where the schedule leaves them alone "
            + "for a fortnight.":
            "%1$d із %2$d слів, що мають визначення, отримали чотири правильні "
            + "відповіді поспіль — саме тоді розклад залишає їх у спокої на два "
            + "тижні.",
        "None of these words has a definition yet, so none of them can be "
            + "tested. Open Cards and sort by \"Without a definition first\".":
            "Жодне з цих слів ще не має визначення, тож жодне не можна перевірити "
            + "тестом. Відкрийте «Картки» і виберіть сортування «Спершу без "
            + "визначення».",

        "Practice this set from the beginning": "Пройти цей набір спочатку",
        "Practice this set from the beginning?": "Пройти цей набір спочатку?",
        "Puts all of it back to unseen so you can work through the same "
            + "questions again. Highlights, notes and set-aside are kept.":
            "Повертає весь набір до стану «не переглянуто», щоб пройти ті самі "
            + "питання ще раз. Виділення, нотатки та відкладені питання "
            + "зберігаються.",
        "Forgets every answer behind these charts. Which questions you have "
            + "seen is kept, so your place in the set does not move.":
            "Забуває всі відповіді, на яких побудовані ці графіки. Те, які "
            + "питання ви бачили, зберігається, тож ваше місце в наборі не "
            + "зміниться.",
        "All %1$d questions in \"%2$@\" go back to unseen, and the %3$d "
            + "answers behind these charts are forgotten. Your highlights, your "
            + "notes and the questions you set aside are all kept.":
            "Усі %1$d {питання|питання|питань} набору «%2$@» повернуться до стану «не "
            + "переглянуто», а %3$d {відповідь|відповіді|відповідей}, на "
            + "{якій|яких|яких} побудовані ці графіки, {буде забута|будуть забуті|будуть забуті}. Ваші виділення, нотатки та відкладені питання "
            + "зберігаються.",
        "Starting over": "Почати спочатку",
        "Deal today\'s words again": "Роздати сьогоднішні слова заново",
        "Puts today\'s new words back and takes the next ones instead. "
            + "Nothing answered is lost.":
            "Повертає сьогоднішні нові слова назад і бере натомість наступні. "
            + "Нічого з відповідей не втрачається.",
        "Deal again": "Роздати заново",
        "Put today\'s new words back?": "Повернути сьогоднішні нові слова?",
        "Put them back": "Повернути",
        "Today\'s set is dealt again from the top of the deck. Nothing you "
            + "have already answered is lost — those words keep their record.":
            "Сьогоднішній набір буде роздано заново з початку колоди. Нічого з "
            + "того, на що ви вже відповіли, не втрачається — ці слова "
            + "збережуть свій запис.",
        "Clear your run": "Очистити серію",
        "Clear your run?": "Очистити серію?",
        "Clear the run": "Очистити серію",
        "Forgets the streak and the days you finished. The words keep what "
            + "they know.":
            "Забуває серію та дні, які ви завершили. Слова зберігають усе, що "
            + "про них відомо.",
        "The streak and the list of days you finished are forgotten. The "
            + "words themselves keep everything they know.":
            "Серія та список завершених днів будуть забуті. Самі слова "
            + "збережуть усе, що про них відомо.",
        "Start this deck over": "Почати цю колоду спочатку",
        "Start this deck over?": "Почати цю колоду спочатку?",
        "Start over": "Почати спочатку",
        "Every word back to never having been seen — times right, times "
            + "skipped, review dates and your run. The words and their "
            + "meanings are kept.":
            "Кожне слово повертається до стану «жодного разу не бачив» — "
            + "правильні відповіді, проминання, дати повторення та ваша серія. "
            + "Самі слова та їхні значення зберігаються.",
        "Every word in \"%@\" goes back to never having been seen: the "
            + "times right, the times skipped, the review dates and your run. "
            + "The words, their meanings and your stars are kept.":
            "Кожне слово в колоді «%@» повернеться до стану «жодного разу не "
            + "бачив»: правильні відповіді, проминання, дати повторення та ваша "
            + "серія. Слова, їхні значення та ваші зірочки зберігаються.",

        "Stealth Mode": "Нічний режим",
        "For studying at night in a room where somebody else is asleep. One switch, because at that hour you should not have to find three.":
            "Для навчання вночі в кімнаті, де хтось уже спить. Один перемикач, бо о такій порі не варто шукати три.",
        "Dark test screen, and nothing from this app makes a sound":
            "Темний екран тесту, і жодного звуку від цього застосунку",
        "The whole app is drawn on black — the test screen, the results, your highlights and the formula sheet included — and the figures from your PDFs are inverted so they are not the one bright thing left on the page. Reminders from this app are silenced, and none are shown at all while you are sitting a test. It changes nothing outside this app — if you want the whole computer quiet, that is a setting of its own.":
            "Увесь застосунок малюється на чорному — разом з екраном тесту, результатами, вашими виділеннями та аркушем формул, — а рисунки з ваших PDF інвертуються, щоб не лишитися єдиним яскравим на сторінці. Нагадування від цього застосунку стають беззвучними, а під час тесту не показуються взагалі. Поза цим застосунком нічого не змінюється — якщо ви хочете тиші на всьому комп'ютері, для цього є окреме налаштування.",
        "The real test is on a white screen. Worth turning this off for a full practice test in the daytime, so test day is not the first time you see it.":
            "Справжній тест — на білому екрані. Варто вимкнути це для повного пробного тесту вдень, щоб день іспиту не був першим разом, коли ви його бачите.",
        "Turn Stealth Mode on": "Увімкнути нічний режим",
        "Turn Stealth Mode off": "Вимкнути нічний режим",
        "Draw this on black, and keep the app quiet.":
            "Малювати це на чорному й тримати застосунок тихим.",
        "Back to the white screen the real test uses.":
            "Повернутися до білого екрана, як на справжньому тесті.",

        "Your run is still here, if you want it": "Ваша серія ще тут, якщо ви хочете",
        "Days you set aside are skipped, the way a planned rest day is — never counted as days you practiced. Your best run and everything you have answered stay exactly as they are.":
            "Відкладені дні пропускаються так само, як запланований день відпочинку, — вони ніколи не рахуються як дні практики. Ваша найкраща серія та всі ваші відповіді залишаються незмінними.",
        "Entirely up to you. A run of days is worth having only while it is helping.":
            "Це цілком ваш вибір. Серія днів має сенс лише доти, доки вона допомагає.",
        "Leave it": "Залишити як є",
        "Welcome back": "З поверненням",
        "Some saved work could not be read, so it was kept aside, untouched, as a “.damaged” file in the app's folder.":
            "Частину збережених даних не вдалося прочитати, тому їх відкладено без змін як файл «.damaged» у теці застосунку.",
        "Answer %1$@: %2$@": "Відповідь %1$@: %2$@",
        "Answer %@": "Відповідь %@",
        "History": "Історія",
        "No finished practice in this set yet. Each test you finish is kept here, with every answer.": "У цьому наборі ще немає завершених тренувань. Кожен тест, який ви завершите, зберігається тут разом з усіма відповідями.",
        "That practice could not be opened.": "Не вдалося відкрити це тренування.",
        "selected": "вибрано",
        "crossed out": "викреслено",
        "Passage": "Текст",
        "Hide the timer": "Сховати таймер",
        "Show the timer": "Показати таймер",
        "Cross out choice %@": "Закреслити варіант %@",
        "Hide this": "Сховати це",
        "Pick up anywhere — a short sitting counts.":
            "Почніть із чого завгодно — навіть коротке заняття має значення.",
        "%1$@ and %2$@": "%1$@ та %2$@",
        "Worth going back over %@ first.": "Варто спершу повторити: %@.",

        "Study together": "Навчатися разом",
        "Two of you, one computer, taking turns: you answer the first question, they answer the second, and so on to the end. Each answer goes into that student's own record, so neither of you ends up with the other's statistics.":
            "Вас двоє, один комп'ютер, по черзі: ви відповідаєте на перше запитання, друга людина — на друге, і так до кінця. Кожна відповідь потрапляє до власного запису того, хто її дав, тож ніхто з вас не отримає чужої статистики.",
        "Who is with you": "Хто з вами",
        "your turn": "ваша черга",
        "That student is no longer on this computer.":
            "Цього учня більше немає на цьому комп'ютері.",

        "Keep a copy somewhere else": "Зберігайте копію в іншому місці",
        "You have never made one.": "Ви ще жодної не зробили.",
        "Copied today.": "Скопійовано сьогодні.",
        "Everything of yours — progress, statistics, highlights, notes, flashcards and study plans — is one small file. It is not the question sets: those are your own PDFs and you can import them again. Send it to yourself and it survives this computer.":
            "Усе ваше — прогрес, статистика, виділення, нотатки, картки та плани навчання — це один невеликий файл. Це не набори запитань: то ваші власні PDF, які ви можете імпортувати знову. Надішліть його собі, і він переживе цей комп'ютер.",
        "Send it…": "Надіслати…",
        "Not now": "Не зараз",
        "Save it where you can send it from — a mail draft, a chat to yourself, or a USB stick.":
            "Збережіть його там, звідки зможете надіслати, — у чернетці листа, у чаті самому собі або на USB-накопичувачі.",
        "Saved %1$@ · %2$d KB": "Збережено %1$@ · %2$d КБ",

        "Exported": "Експортовано",
        "Show me the file": "Показати файл",

        "Turn about": "По черзі",
        "Side by side": "Пліч-о-пліч",
        "One question on the screen at a time. You answer the first, they answer the second. You both see every question, and you can highlight and take notes.":
            "На екрані одне запитання за раз. Ви відповідаєте на перше, друга людина — на друге. Ви обоє бачите всі запитання й можете виділяти текст і робити нотатки.",
        "The screen is split in two and you both work at the same time, each on your own half of the questions. Faster, and nobody is waiting — but each of you has half the screen, and there are no highlights or notes in this one.":
            "Екран поділено навпіл, і ви працюєте одночасно, кожен над своєю половиною запитань. Швидше, і ніхто не чекає — але кожному дістається пів екрана, і в цьому режимі немає виділень і нотаток.",
        "How you want to work": "Як ви хочете працювати",
        "Everything below is yours to set as usual — how many questions, which ones, and a clock if you want one. A full test is the one thing a sitting for two cannot be: its second module is chosen by how a single student did in the first.":
            "Усе нижче налаштовується як завжди — скільки запитань, які саме та чи потрібен таймер. Єдине, чим заняття для двох бути не може, — це повний тест: його другий модуль добирається за тим, як склав перший один учень.",
        "for both of you": "для вас обох",
        "Both of you will see your own results, and each answer goes into that student's own record.":
            "Кожен з вас побачить власний результат, і кожна відповідь потрапляє до власного запису того, хто її дав.",
        "Each answer goes into that student's own record.":
            "Кожна відповідь потрапляє до власного запису того, хто її дав.",
        "All done — waiting for the other one to finish.":
            "Усе готово — чекаємо, доки завершить друга людина.",
        "The card that sets up a sitting for two students on one computer. It only appears when there is more than one student on this computer anyway; turn it off and it will not appear at all.":
            "Картка, яка налаштовує заняття для двох учнів за одним комп'ютером. Вона й так з'являється лише тоді, коли на цьому комп'ютері більше одного учня; вимкніть її — і вона не з'являтиметься взагалі.",
        "Both of you are done.": "Ви обоє завершили.",
        "Every question has been answered or passed over. Keep working to go back over any of them, or end the test now.":
            "На кожне запитання дано відповідь або його пропущено. Продовжуйте, щоб переглянути будь-яке з них, або завершіть тест зараз.",
        "You have both finished": "Ви обоє завершили",
        "Leave": "Вийти",
        "done": "готово",
        "Stealth Mode is on, so the whole app is black and the paper below is not in use. Turn it off and you are back on the one you picked.":
            "Нічний режим увімкнено, тож увесь застосунок чорний, а обраний нижче папір не використовується. Вимкніть його — і ви повернетеся до того, який обрали.",
        "A plain-language summary on the statistics screen, in whichever language is set, that can be saved as a one-page PDF. Off if there is nobody to show it to.":
            "Зрозумілий підсумок на екрані статистики, тією мовою, яку обрано, який можна зберегти як PDF на одну сторінку. Вимкніть, якщо немає кому його показувати.",
        "The card that offers to write everything of yours out as one file, and the reminder to do it. Turning it off does not stop you exporting — Storage below still will — it only stops the asking.":
            "Картка, яка пропонує записати все ваше одним файлом, і нагадування зробити це. Вимкнення не заважає експортувати — розділ «Сховище» нижче це вміє, — воно лише припиняє нагадування.",
        "The page for a parent":
            "Сторінка для батьків",
        " and ": "та",
        "%1$d R&W · %2$d math": "%1$d ЧП · %2$d математика",
        "%1$d min is %2$@ a question; the test would allow %3$d min for these %4$d":
            "%1$d хв — це %2$@ на запитання; справжній тест дав би %3$d хв на ці %4$d",
        "%1$d/%2$d correct": "%1$d/%2$d правильно",
        "%@ a question, the pace the test sets":
            "%@ на запитання — темп, який задає тест",
        "%d marked for review": "позначено для перегляду: %d",
        "%d unanswered": "без відповіді: %d",
        "(passage changed)": "(текст змінився)",
        "22 · math module": "22 · модуль математики",
        "27 · R&W module": "27 · модуль читання та письма",
        "A free, non-profit study tool from United States Universities For Ukraine, built for Ukrainian students preparing for university in the United States.":
            "Безкоштовний некомерційний навчальний інструмент від United States Universities For Ukraine, створений для українських учнів, які готуються до вступу в університет у США.",
        "All (%d)": "Усі (%d)",
        "All questions are answered.": "На всі запитання дано відповідь.",
        "An adaptive test draws module 1 and both forms of module 2 from the set, so each section needs enough questions at every difficulty. Still short —":
            "Адаптивний тест бере з набору модуль 1 і обидва варіанти модуля 2, тож у кожній секції потрібно достатньо запитань кожного рівня складності. Ще бракує —",
        "Answer preview: %@": "Ваша відповідь: %@",
        "A−/A+ resize the question, and so do Ctrl or Command with + and −.":
            "A−/A+ змінюють розмір запитання, як і Ctrl або Command із + та −.",
        "Bring this choice back": "Повернути цей варіант",
        "Choose PDFs to add to “%@”": "Виберіть PDF-файли, щоб додати до «%@»",
        "Choose one or more PDFs exported from the College Board Question Bank":
            "Виберіть один або кілька PDF-файлів, експортованих з банку запитань College Board",
        "Correct answer:  %@": "Правильна відповідь:  %@",
        "Could not create the PDF context.": "Не вдалося створити контекст PDF.",
        "Could not create the PDF.": "Не вдалося створити PDF.",
        "Could not export: %@": "Не вдалося експортувати: %@",
        "After the update, some highlights no longer matched their words and were taken off; their notes are kept.":
            "Після оновлення деякі виділення більше не збігалися зі своїми словами, тож їх знято; нотатки до них збережено.",
        "%d s":
            "%d с",
        "%1$dm %2$@s": "%1$d хв %2$@ с",
        "%1$d h %2$d min":
            "%1$d год %2$d хв",
        "Could not read that set again; it has been left as it was.":
            "Не вдалося перечитати цей набір; його залишено як був.",
        "Could not save the copy: %@": "Не вдалося зберегти копію: %@",
        "Cross out this choice": "Викреслити цей варіант",
        "Edit note": "Змінити нотатку",
        "Got right (%d)": "Правильно (%d)",
        "Got wrong (%d)": "Помилки (%d)",
        "Imported %d questions": "Імпортовано %d {запитання|запитання|запитань}",
        "In the College Board Question Bank — SAT or PSAT — pick the questions you want and choose Export. Import that PDF here and it becomes a practice test you can sit as many times as you like.":
            "У банку запитань College Board — SAT або PSAT — оберіть потрібні запитання й натисніть Export. Імпортуйте цей PDF сюди, і він стане тренувальним тестом, який можна складати скільки завгодно разів.",
        "Loaded %d saved questions": "Завантажено %d {збережене запитання|збережені запитання|збережених запитань}",
        "Mark for Review flags a question so you can find it again; the list at the foot of the screen jumps to any question.":
            "«Позначити для перегляду» помічає запитання, щоб ви знайшли його знову; список унизу екрана переходить до будь-якого запитання.",
        "Marks are going missing on easy questions too, which usually means care rather than knowledge.":
            "Бали втрачаються і на легких запитаннях — зазвичай це питання уважності, а не знань.",
        "Match the real test": "Як у справжньому тесті",
        "Matching the real test": "Як у справжньому тесті",
        "Module 1 is a mix of all three difficulties. How it goes decides whether module 2 is the easier or the harder form, the way the real test routes you.":
            "Модуль 1 змішує всі три рівні складності. Від того, як ви його складете, залежить, чи буде модуль 2 легшим, чи важчим — так само, як у справжньому тесті.",
        "Module 2 is simply the next set of questions. Turn this on to be routed to an easier or harder module 2 by how module 1 goes.":
            "Модуль 2 — це просто наступний набір запитань. Увімкніть, щоб модуль 2 добирався легшим або важчим залежно від модуля 1.",
        "No questions could be read from those files.":
            "З цих файлів не вдалося прочитати жодного запитання.",
        "No questions match these settings yet.":
            "Поки що жодне запитання не відповідає цим налаштуванням.",
        "No questions were found in “%@”.": "У «%@» не знайдено запитань.",
        "Not quite — the answer is %@": "Не зовсім — правильна відповідь %@",
        "Nothing is due for review yet. Answer some questions and they come back on a widening schedule.":
            "Поки немає нічого для повторення. Дайте відповіді на кілька запитань — вони повертатимуться з дедалі більшими проміжками.",
        "Nothing is due yet — the next question comes back %@.":
            "Поки нічого — наступне запитання повернеться %@.",
        "Nothing to show here.": "Тут нічого показувати.",
        "Question %1$d of %2$d · module %3$d of %4$d":
            "Питання %1$d із %2$d · модуль %3$d із %4$d",
        "Question %@: no correct answer found — skipped.":
            "Запитання %@: не знайдено правильної відповіді — пропущено.",
        "Question %@: no question text found — skipped.":
            "Запитання %@: не знайдено тексту запитання — пропущено.",
        "Question sets, progress, highlights, notes, saved sittings and your imported PDFs all live in one folder. Copy it to back everything up.":
            "Набори запитань, прогрес, виділення, нотатки, збережені заняття та імпортовані PDF — усе лежить в одній теці. Скопіюйте її, щоб зробити резервну копію всього.",
        "R&W": "ЧП",
        "SAT Practice — Questions to Review": "Практика SAT — запитання для повторення",
        "SAT Practice — Set Aside": "Практика SAT — відкладені",
        "SAT review — %@.pdf": "Повторення SAT — %@.pdf",
        "SAT set aside — %@.pdf": "Відкладені SAT — %@.pdf",
        "Save a copy of this PDF": "Зберегти копію цього PDF",
        "Set aside keeps a question in a pile you can practice or export later. Unlike Mark for Review, it outlives this sitting.":
            "«Відкласти» тримає запитання в стосі, який можна попрактикувати чи експортувати пізніше. На відміну від позначки для перегляду, він переживе це заняття.",
        "Solid on easy questions and dropping sharply on hard ones — the gap is knowledge, not carelessness.":
            "Упевнено на легких і різкий спад на важких — річ у знаннях, а не в неуважності.",
        "The answer eliminator — ABC — crosses out choices you have ruled out.":
            "Закреслювач — ABC — викреслює варіанти, які ви вже відкинули.",
        "The number of degrees of arc in a circle is 360.":
            "Кількість градусів дуги в колі — 360.",
        "The number of radians of arc in a circle is 2π.":
            "Кількість радіанів дуги в колі — 2π.",
        "The sum of the measures in degrees of the angles of a triangle is 180.":
            "Сума градусних мір кутів трикутника — 180.",
        "There are no questions matching those settings.":
            "Немає запитань, що відповідають цим налаштуванням.",
        "There are not enough questions at each difficulty for an adaptive test.":
            "Недостатньо запитань на кожному рівні складності для адаптивного тесту.",
        "There are not enough questions for a full test.":
            "Недостатньо запитань для повного тесту.",
        "There is no clock on this sitting. Take the time you need.":
            "У цьому занятті немає таймера. Витрачайте стільки часу, скільки потрібно.",
        "This app reads the PDF that the College Board Question Bank produces when you choose Export — SAT or PSAT. Make sure the file still has its “Question ID” headers and has not been re-saved or printed to a new PDF.":
            "Застосунок читає PDF, який створює банк запитань College Board, коли ви обираєте Export — SAT або PSAT. Переконайтеся, що у файлі збереглися заголовки «Question ID» і що його не перезбережено та не роздруковано в новий PDF.",
        "This ends the test and shows your results.":
            "Це завершує тест і показує ваші результати.",
        "Time to practice": "Час потренуватися",
        "Typing an answer": "Введення відповіді",
        "Working through the section": "Як працювати над розділом",
        "You cannot come back to this module once it is handed in, the same as on the real test.":
            "Після здавання повернутися до цього модуля не можна — так само, як у справжньому тесті.",
        "You have %@.": "У вас %@.",
        "Your accuracy holds up as the questions get harder.":
            "Ваша точність тримається, коли запитання стають складнішими.",
        "Your answer": "Ваша відповідь",
        "Your streak ends tonight": "Ваша серія завершується сьогодні",
        "answered": "відповіді",
        "axis of symmetry": "вісь симетрії",
        "dashed: the line itself is not included": "пунктир: сама пряма не входить",
        "exponential — multiplies": "експоненційна — множить",
        "graded as you go": "оцінювання одразу",
        "line of best fit": "лінія найкращого наближення",
        "mean 33": "середнє 33",
        "mean 86.4": "середнє 86,4",
        "median 33": "медіана 33",
        "median 34": "медіана 34",
        "linear — adds the same amount": "лінійна — додає однаково",
        "of %d seen": "з %d переглянуто",
        "the four salaries alone": "лише чотири зарплати",
        "with 300 added": "після додавання 300",
        "overall": "загалом",
        "question kept back": "запитання відкладено",
        "shaded above the line": "зафарбовано над прямою",
        "slope = the rate, in the units of the axes":
            "нахил = швидкість зміни, в одиницях осей",
        "the two a's are equal": "обидва кути a рівні",
        "today": "сьогодні",
        "typical question": "типове запитання",
        "x-intercepts": "нулі функції",
        "your bank": "вашого набору",
        "“%@” could not be read as a PDF.": "«%@» не вдалося прочитати як PDF.",
        "“%@” will be removed from this app. Copies you saved elsewhere are untouched.":
            "«%@» буде вилучено із застосунку. Копії, збережені деінде, залишаться недоторканими.",
        "“%@” will be removed from this app. The questions already imported from it stay, and any copy you keep elsewhere is untouched.":
            "«%@» буде вилучено із застосунку. Запитання, вже імпортовані з нього, залишаються, а будь-яка копія деінде — недоторканою.",
        "%d more to keep today": "ще %d, щоб утримати сьогодні",
        "questions kept back": "запитань відкладено",
        "Your other sets": "Ваші інші набори",
        "You have answered questions in these. Statistics are kept per set, so choose one to see how it is going.":
            "У них ви вже відповідали на запитання. Статистика ведеться окремо для кожного набору — оберіть один, щоб побачити, як справи.",
        "paused": "на паузі",
        "You have a test in progress in this set": "У цьому наборі є незавершений тест",
        "No topic stands out as much stronger or weaker than the rest yet.":
            "Поки жодна тема не виділяється як помітно сильніша чи слабша за інші.",
        "Not answered (%d)": "Без відповіді (%d)",
        "Nothing wrong — every question you answered was correct.":
            "Жодної помилки — усі запитання, на які ви відповіли, правильні.",
        "Every question was answered.": "На всі запитання дано відповідь.",
        "Nearly all of it is the figures drawn out of your PDFs. A set can be removed from the practice screen, under the PDFs it was built from.":
            "Майже все це — рисунки, витягнуті з ваших PDF. Набір можна вилучити на екрані практики, у розділі PDF-файлів, з яких його зібрано.",
        "Everything in this folder": "Усе в цій теці",
        "This is a test version. Your work is kept as usual.":
            "Це тестова версія. Ваша робота зберігається як завжди.",
        "Not affiliated with the College Board. Everything stays on your computer.":
            "Не пов'язано з College Board. Усі дані залишаються на вашому комп'ютері.",

        "Grading": "Оцінювання",
        "Bringing your question sets up to date…":
            "Оновлюємо ваші набори питань…",
        "Reading again": "Читаємо знову",
        "Nothing to practice": "Немає чого практикувати",
        "%d-day streak ends tonight":
            "Серія з %d {дня|днів|днів} завершується сьогодні ввечері",
        "%@ stopped": "%@ зупинився",
        "Something went wrong and %@ had to stop.":
            "Щось пішло не так, і %@ довелося зупинитися.",
        "The details were saved to:%@":
            "Подробиці збережено до:%@",
        "Start a new one":
            "Почати нову",
        "Deal them again":
            "Роздати їх знову",
        "Clear it":
            "Очистити",
        "“%@” will be removed from this deck.":
            "«%@» буде вилучено з цієї колоди.",
        "Hand it in":
            "Здати",
        "The imported questions and your progress for this set will be removed. Your original PDF files are not touched.":
            "Імпортовані питання та ваш поступ у цьому наборі буде вилучено. Ваші оригінальні PDF-файли лишаються незмінними.",
        "Choose PDFs exported from the College Board Question Bank":
            "Виберіть PDF-файли, експортовані з банку питань College Board",
        "Could not import":
            "Не вдалося імпортувати",
        "Imported with notes":
            "Імпортовано із зауваженнями",
        "Could not read that set again":
            "Не вдалося прочитати цей набір знову",
        "Nothing was changed.":
            "Нічого не змінено.",
        "Export the questions you set aside":
            "Експортувати відкладені питання",
        "Could not export":
            "Не вдалося експортувати",
        "Empty it":
            "Очистити",
        "Could not save":
            "Не вдалося зберегти",
        "The questions already imported from it stay, and any copy you keep elsewhere is untouched.":
            "Питання, вже імпортовані з нього, лишаються, і будь-яка копія, збережена деінде, лишається незмінною.",
        "Copies you saved elsewhere are untouched.":
            "Копії, збережені деінде, лишаються незмінними.",
        "“%@” will be removed from this app.":
            "«%@» буде вилучено з цього застосунку.",
        "Export missed questions":
            "Експортувати пропущені питання",
        "You can open or print this PDF, and you can import it back into %@ to practice these questions again.":
            "Ви можете відкрити або надрукувати цей PDF, а також імпортувати його назад у %@, щоб потренувати ці питання знову.",
        "Pick a day":
            "Виберіть день",
        "A plan with no days is a plan to do nothing. Choose at least one, or turn the plan off.":
            "План без днів — це план нічого не робити. Виберіть щонайменше один або вимкніть план.",
        "Export student":
            "Експортувати учня",
        "Import a student file":
            "Імпортувати файл учня",
        "%1$@ — matched to your “%2$@”, %3$d questions in common (%4$d records)":
            "%1$@ — зіставлено з вашим «%2$@», спільних питань: %3$d (записів: %4$d)",
        "Import %@?":
            "Імпортувати %@?",
        "Clear them":
            "Очистити",
        "Throw it away":
            "Відкинути",
        "%@ is working at about the same level across every topic there is enough practice to judge — nothing yet stands out as either a strength or a difficulty.":
            "%@ працює приблизно на одному рівні в усіх темах, де вже досить практики, щоб судити, — поки що ніщо не вирізняється ані як сильна сторона, ані як труднощі.",
        "Imported question bank":
            "Імпортований банк питань",
        "Review export":
            "Експорт для повторення",
        "“%@” has no pages.":
            "У «%@» немає сторінок.",
        "No usable questions were found in “%@”.":
            "У «%@» не знайдено придатних запитань.",
        "This app reads the PDF that the College Board Question Bank produces when you choose Export. Make sure the file still has its “Question ID” headers and has not been re-saved or printed to a new PDF.":
            "Цей застосунок читає PDF, який створює банк питань College Board, коли ви обираєте Export. Переконайтеся, що у файлі збереглися заголовки «Question ID» і що його не перезбережено та не надруковано в новий PDF.",
        "Nothing is due yet — the next question comes back in about %@.":
            "Поки що нічого повторювати — наступне запитання повернеться приблизно через %@.",
        "%@ — you have not imported this set here yet; its progress will be kept until you do.":
            "%@ — ви ще не імпортували цей набір сюди; його поступ збережеться, доки не імпортуєте.",
        " (%d records)":
            " (записів: %d)",
        "Not enough attempts yet to say which skills are weakest. Answer at least 5 questions in a skill and it can be ranked.":
            "Поки що замало відповідей, щоб сказати, які навички найслабші. Дайте щонайменше 5 відповідей у навичці, і її можна буде оцінити.",
        "Reduce motion is on, so cards turn without an animation. Turn it off above and the choice comes back.":
            "Зменшення руху увімкнено, тож картки перевертаються без анімації. Вимкніть його вище — і вибір повернеться.",
        "%1$d questions set aside from %2$@":
            "%1$d {запитання|запитання|запитань} відкладено з %2$@",
        "One more question keeps it.":
            "Ще одне питання — і вона триває.",
        "One question left today.":
            "Сьогодні лишилося одне питання.",
        "Minimize":
            "Згорнути",
        "Maximize":
            "Розгорнути",
        "Restore":
            "Відновити",
        "Back to your results":
            "Назад до ваших результатів",
        "Check your work":
            "Перевірте свою роботу",
        "Discard sitting":
            "Відхилити сесію",
        "Discard this sitting?":
            "Відхилити цю сесію?",
        "Drop the PDF to import it":
            "Відпустіть PDF, щоб імпортувати його",
        "Every question here, and which ones you have answered. Choose one to go back to it; hand the section in when you are ready.":
            "Усі питання тут — і на які ви вже відповіли. Виберіть питання, щоб повернутися до нього; здайте секцію, коли будете готові.",
        "Go to Review Page":
            "Перейти до сторінки перегляду",
        "Hand in this module and go on to the next.":
            "Здати цей модуль і перейти до наступного.",
        "It is deleted: where you had got to, the answers given in it and the time left. This cannot be undone.":
            "Її буде видалено: де ви зупинилися, дані в ній відповіді та залишок часу. Це неможливо скасувати.",
        "Nothing was imported":
            "Нічого не імпортовано",
        "Optional":
            "Необов'язково",
        "Pace the rest of the section by the clock.":
            "Розподіліть решту часу секції за годинником.",
        "Results":
            "Результати",
        "Test complete":
            "Тест завершено",
        "%1$d modules · %2$d questions · %3$d min · every module timed as on the test":
            "%1$d {модуль|модулі|модулів} · %2$d {питання|питання|питань} · %3$d хв · кожен модуль на час, як на тесті",
        "Every question in that file is already in “%@”, so no new set was made.":
            "Усі питання з цього файлу вже є в «%@», тож новий набір не створено.",
        "Of those, %1$d answered correctly — %2$d%%.":
            "З них правильно відповіли на %1$d — %2$d%%.",
    ]
}

extension String {
    func ranges(ofPattern pattern: String) -> [Range<String.Index>] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let whole = NSRange(startIndex..., in: self)
        return regex.matches(in: self, range: whole).compactMap { Range($0.range, in: self) }
    }
}
