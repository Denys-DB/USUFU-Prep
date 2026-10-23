import Foundation

enum Legal {

    static let lastUpdated = "30 September 2026"
    static let contactEmail = "support@usufu.org"
    static let operatorName = "United States Universities For Ukraine"
    static let governingState = "Connecticut"

    static var copyright: String { "\(operatorName) © 2026. All rights reserved." }

    static var footprint: String {
        L("Not affiliated with the College Board. "
          + "Everything stays on your computer.")
    }

    struct Section: Identifiable {
        var id: String { title }
        var title: String
        var paragraphs: [String]
    }

    struct Document: Identifiable {
        var id: String { title }
        var title: String
        var summary: String
        var sections: [Section]
    }

    private static let bilingualClause =
        "This document may be provided in more than one language; if the "
        + "versions differ in meaning, the English version governs."

    private static func contact(_ subject: String) -> Section {
        Section(title: "Contact Us", paragraphs: [
            "If you have questions about \(subject), you may contact the Operator "
            + "at \(contactEmail).",
            bilingualClause,
        ])
    }

    static var documents: [Document] {
        switch Localisation.current {
        case .ukrainian: return documentsUK
        case .spanish: return documentsES
        case .portuguese: return documentsPT
        default: return englishDocuments
        }
    }

    static var englishDocuments: [Document] { [privacy, terms, accessibility] }

    static let privacy = Document(
        title: "Privacy Policy",
        summary: "What the App stores, where it stores it, and why none of it reaches us.",
        sections: [
            Section(title: "Scope of This Policy", paragraphs: [
                "This Privacy Policy explains what information is collected, used, and "
                + "retained in connection with your use of \(Brand.appName) (the \"App\"), "
                + "which is operated by \(operatorName), an independent educational "
                + "initiative (the \"Operator\").",
                "This Policy applies to the App only, and it does not apply to the "
                + "Operator's website, to the College Board's Question Bank or any other "
                + "service from which you may obtain question material, or to any other "
                + "third-party website or service.",
                "By using the App, you acknowledge that you have read and understood this "
                + "Policy.",
            ]),
            Section(title: "The App Does Not Require an Account", paragraphs: [
                "The App does not require you to register, log in, or create any account, "
                + "and it does not charge for or process any payments.",
            ]),
            Section(title: "The App Operates Entirely on Your Own Device", paragraphs: [
                "The App makes no network connections of any kind. It does not transmit "
                + "any information to the Operator or to any third party, and it contains "
                + "no analytics, telemetry, advertising, or crash reporting.",
                "Everything the App holds — the question sets you import, the original "
                + "PDF files, your answers, your progress and attempt history, your "
                + "highlights and notes, your saved sittings, your shelves, and your "
                + "settings — is stored only in the App's own folder on your device.",
                "The Operator does not receive, transmit, collect, or store any of this "
                + "information, and the Operator has no ability to view, recover, or "
                + "restore it if it is lost or deleted from your device.",
                "You can open that folder from within the App at any time in order to "
                + "inspect, copy, back up, or delete its contents.",
                "You are responsible for safeguarding any device on which you use the "
                + "App, since information stored locally can be viewed by anyone with "
                + "access to that device or user account.",
            ]),
            Section(title: "Several Students on One Device", paragraphs: [
                "The App allows more than one student to use the same computer, each "
                + "with their own progress, statistics, notes, flashcard decks, "
                + "language, and settings. Question sets are shared between them; "
                + "everything personal is kept separately.",
                "These student profiles are a convenience, not a security measure. "
                + "**They are not protected by a password, a PIN, or any other "
                + "credential, and anyone using the computer can open any of them.** "
                + "They exist so that two students do not overwrite each other's work, "
                + "not to keep one student's work private from the other.",
                "If you need your work to be private from other people who use the same "
                + "computer, use a separate operating-system user account, which the App "
                + "cannot see across.",
                "When two students answer questions together in the same sitting, each "
                + "answer is recorded only against the student whose turn it was.",
            ]),
            Section(title: "Taking Your Work to Another Device", paragraphs: [
                "The App can write everything personal belonging to one student out as a "
                + "single file, so that it can be moved to another computer. Creating "
                + "that file, and choosing where it goes, is entirely your decision and "
                + "your action.",
                "Once you have exported such a file, it is an ordinary file on your "
                + "device and is no longer protected by the App. If you email it, copy "
                + "it to a shared drive, or leave it on a removable disk, anyone who "
                + "obtains it can read the study data inside it. It is not encrypted.",
                "Only import a student file that you created yourself or received from "
                + "someone you trust.",
            ]),
            Section(title: "Reminders", paragraphs: [
                "If you turn on study reminders, the App asks your operating system for "
                + "permission to show notifications and schedules them locally on your "
                + "device. No reminder is sent through any server, and the App does not "
                + "learn whether you saw one.",
            ]),
            Section(title: "Material You Import", paragraphs: [
                "The App contains no question content of its own. All practice material "
                + "comes from PDF files that you obtain yourself and choose to import.",
                "Imported files are copied into the App's folder on your device so that "
                + "they can be read again if the App's reader is improved. They are not "
                + "uploaded, shared, or transmitted anywhere.",
            ]),
            Section(title: "No Sale or Sharing of Personal Data", paragraphs: [
                "The Operator does not sell, rent, trade, or share your personal data with "
                + "any third party, because the App does not collect or transmit any "
                + "personal data to begin with.",
            ]),
            Section(title: "Children's Privacy", paragraphs: [
                "The App is an educational resource intended to be useful to students "
                + "preparing for the SAT and PSAT, and the Operator recognizes that many "
                + "of its users will be minors.",
                "The App does not knowingly collect personal data from users of any age, "
                + "including children under 13, because it collects no personal data and "
                + "transmits nothing from your device.",
                "The Operator encourages minors to use the App together with a parent, "
                + "guardian, or teacher.",
            ]),
            Section(title: "International Users, Ukraine, and the European Union",
                    paragraphs: [
                "The App is used by students located in Ukraine, the European Union, the "
                + "United States, and other countries, and data protection laws differ "
                + "among these jurisdictions.",
                "The Operator minimizes the personal data it collects by design, since the "
                + "App stores data only on your own device and the Operator receives none "
                + "of it.",
                "Because all data associated with your use of the App remains on your own "
                + "device, you can exercise complete control over that data at any time by "
                + "deleting it from the App's folder.",
            ]),
            Section(title: "Security", paragraphs: [
                "Because the App transmits nothing, the security of your information "
                + "depends on the security of the device it is stored on.",
                "No method of electronic storage is completely secure, and the Operator "
                + "cannot guarantee absolute security.",
            ]),
            Section(title: "Changes to This Policy", paragraphs: [
                "The Operator may update this Policy from time to time to reflect changes "
                + "in the App or for legal or operational reasons.",
                "The date shown with this Policy indicates when it was last revised, and "
                + "continued use of the App after an update constitutes your acceptance of "
                + "the revised Policy.",
            ]),
            contact("this Privacy Policy or about how your information is handled"),
        ])

    static let terms = Document(
        title: "Terms of Service",
        summary: "What the App is for, what it does not promise, and the limits of our liability.",
        sections: [
            Section(title: "Acceptance of These Terms", paragraphs: [
                "These Terms of Service (the \"Terms\") govern your access to and use of "
                + "\(Brand.appName) (the \"App\"), operated by \(operatorName), an "
                + "independent educational initiative (the \"Operator\").",
                "By installing or using the App, you agree to be bound by these Terms, and "
                + "if you do not agree to these Terms, you must not use the App.",
                "If you are a minor, the Operator recommends that you review these Terms "
                + "together with a parent, guardian, or teacher before using the App.",
            ]),
            Section(title: "No Affiliation With the College Board", paragraphs: [
                "SAT® is a registered trademark of the College Board. PSAT/NMSQT® is a "
                + "registered trademark of the College Board and the National Merit "
                + "Scholarship Corporation. PSAT™ 10 and PSAT™ 8/9 are trademarks of the "
                + "College Board. Bluebook™ is the College Board's own testing "
                + "application.",
                "Neither the College Board nor the National Merit Scholarship Corporation "
                + "is affiliated with, sponsors, endorses, licenses, or has reviewed the "
                + "App or the Operator. These names are used solely to identify the "
                + "examinations for which the App is intended to help you practice, and "
                + "such use is nominative.",
                "The App deliberately resembles the College Board's testing application in "
                + "layout and behavior so that the format holds no surprises on test day. "
                + "The App is not that application, is not connected to it, and cannot be "
                + "used to sit or register for any real examination.",
            ]),
            Section(title: "The App Provides Practice Material Only", paragraphs: [
                "The App is provided solely for general educational and practice purposes "
                + "to help students rehearse the format and pacing of the digital SAT and "
                + "PSAT.",
                "Nothing in the App constitutes accredited test preparation, admissions "
                + "counseling, or professional advice of any kind, and no advisor-client "
                + "relationship of any kind is created by your use of the App.",
            ]),
            Section(title: "Question Material Is Yours, Not the Operator's", paragraphs: [
                "The App is distributed with no question content. All practice material "
                + "comes from files that you obtain and import yourself.",
                "Question material, including its text, figures, and explanations, remains "
                + "the property of its respective owner. The Operator claims no rights in "
                + "it, does not distribute it, and does not transmit it anywhere.",
                "You are responsible for obtaining any material you import lawfully and "
                + "for complying with the terms under which you obtained it, including any "
                + "restriction on sharing it with others.",
            ]),
            Section(title: "No Guarantee of Any Outcome", paragraphs: [
                "Nothing in the App guarantees or implies any particular outcome, "
                + "including any test score, admission to any educational institution, or "
                + "receipt of any scholarship or financial aid.",
                "The App does not produce a scaled SAT or PSAT score, and no result, "
                + "percentage, or statistic it displays should be interpreted as one or "
                + "used to predict one.",
                "Where the App reproduces the structure of the digital test, including its "
                + "module lengths, timings, and the routing of an adaptive second module, "
                + "it does so as an approximation of the published format. The threshold "
                + "the App uses to route between an easier and a harder second module is "
                + "the Operator's own, because the College Board does not publish its own "
                + "criteria, and it should not be understood as reproducing them.",
            ]),
            Section(title: "Imported Material Is Read by Software", paragraphs: [
                "The App reads question material out of your files automatically. This "
                + "process is tested but is not infallible, and it may occasionally "
                + "misread text, an answer, a table, or a figure.",
                "You must verify anything that appears incorrect against your original "
                + "file before concluding that your answer was wrong, and you should not "
                + "rely on the App as an authoritative record of any question or answer.",
            ]),
            Section(title: "Acceptable Use", paragraphs: [
                "You agree to use the App only for lawful purposes and in a manner "
                + "consistent with these Terms.",
                "You agree not to use the App to reproduce, redistribute, or make "
                + "available any question material to any person not entitled to receive "
                + "it.",
                "You agree not to use the App for any unlawful purpose or in violation of "
                + "any applicable local, state, national, or international law or "
                + "regulation.",
            ]),
            Section(title: "Intellectual Property", paragraphs: [
                "The App's software, design, text, and artwork, including the Operator's "
                + "name, seal, and wordmark, are the property of the Operator or its "
                + "licensors and are protected by copyright, trademark, and other "
                + "intellectual property laws. This does not extend to question material "
                + "you import, which is addressed above.",
                "The Operator grants you a limited, revocable, non-exclusive, "
                + "non-transferable license to use the App for your own personal, "
                + "non-commercial educational purposes.",
                "You may not sell the App, offer it as a paid service, or represent it as "
                + "your own or as the product of any other organization.",
            ]),
            Section(title: "This Is a Test Version", paragraphs: [
                "This release of the App is a beta — a test version, marked as such "
                + "beside the App's name. It is provided so that students can try it "
                + "and report problems, and it may contain defects that a finished "
                + "release would not.",
                "Your work is saved in the ordinary way and is not treated differently "
                + "because this is a test version. Even so, while the App is in beta you "
                + "are strongly encouraged to keep your own copy of anything you would "
                + "not want to lose; the App can write everything of yours out as a "
                + "single file for exactly this purpose.",
                "The disclaimers and limitations below apply in full to a test version.",
            ]),
            Section(title: "Disclaimer of Warranties", paragraphs: [
                "The App is provided on an as is and as available basis without warranties "
                + "of any kind, whether express, implied, or statutory.",
                "To the fullest extent permitted by applicable law, the Operator disclaims "
                + "all warranties, including implied warranties of merchantability, "
                + "fitness for a particular purpose, non-infringement, accuracy, and "
                + "uninterrupted or error-free operation.",
                "The Operator does not warrant that the App will be free of errors or "
                + "defects, that any error or defect will be corrected, or that the App "
                + "will read any particular file correctly or completely.",
            ]),
            Section(title: "Limitation of Liability", paragraphs: [
                "To the fullest extent permitted by applicable law, the Operator shall not "
                + "be liable for any direct, indirect, incidental, special, consequential, "
                + "or punitive damages arising out of or in any way connected with your "
                + "use of, or inability to use, the App.",
                "This limitation applies to any decision you make or action you take in "
                + "reliance on the App or on any result it displays, and to any loss of "
                + "data stored by the App, including question sets, progress, notes, or "
                + "imported files.",
                "This limitation applies regardless of the legal theory on which a claim is "
                + "based, whether contract, tort, negligence, strict liability, or "
                + "otherwise, and even if the Operator has been advised of the possibility "
                + "of such damages.",
                "Because the App is offered free of charge, and because some jurisdictions "
                + "do not allow certain limitations of liability, some of the limitations "
                + "in this section may not apply to you, and in such cases the Operator's "
                + "liability will be limited to the greatest extent permitted by "
                + "applicable law.",
            ]),
            Section(title: "Indemnification", paragraphs: [
                "You agree to indemnify, defend, and hold harmless the Operator, its "
                + "officers, contributors, and agents from and against any claims, "
                + "liabilities, damages, losses, and expenses, including reasonable "
                + "attorneys' fees, arising out of or in any way connected with your "
                + "misuse of the App, your violation of these Terms, or your handling of "
                + "any material you import.",
            ]),
            Section(title: "Governing Law", paragraphs: [
                "These Terms are governed by the laws of the State of \(governingState), "
                + "without regard to its conflict-of-laws principles.",
            ]),
            Section(title: "Changes to These Terms", paragraphs: [
                "The Operator may revise these Terms from time to time, and the date shown "
                + "with these Terms indicates when they were last revised.",
                "Your continued use of the App after any revision constitutes your "
                + "acceptance of the revised Terms.",
            ]),
            contact("these Terms"),
        ])

    static let accessibility = Document(
        title: "Accessibility Statement",
        summary: "What the App does to stay usable, and where it falls short.",
        sections: [
            Section(title: "Our Commitment", paragraphs: [
                "The Operator is committed to making \(Brand.appName) usable by as many "
                + "students as possible, including students with disabilities.",
            ]),
            Section(title: "Measures We Have Taken", paragraphs: [
                "Question text can be resized at any time using the A− and A+ controls or "
                + "the Control and Command keys with plus and minus, and the chosen size "
                + "applies to every question and to rendered figures alike.",
                "On macOS the App follows the system's Reduce Motion setting, and on "
                + "Windows it follows the system's Animation effects setting. Linux has "
                + "no single such setting, so there the App relies on its own. On every "
                + "platform it also provides its own setting to reduce motion "
                + "independently of the system.",
                "The App offers a light and a dark theme, and the surfaces that display "
                + "question content are deliberately held to a single high-contrast "
                + "appearance in both, so that material rendered from your files remains "
                + "legible.",
                "A separate Stealth Mode draws the whole App, including those surfaces, "
                + "on black and inverts rendered figures, for students who study at night "
                + "or who find a bright screen uncomfortable. It also silences the App's "
                + "own reminders.",
                "During a test, the controls a student needs — the answer choices, Back "
                + "and Next, Mark for Review, the question list, the timer, the text size "
                + "controls, the reference sheet, the highlighter and the answer "
                + "eliminator — carry names that screen readers announce, and an answer "
                + "can be chosen with its letter key and questions changed with the "
                + "arrow keys.",
            ]),
            Section(title: "Known Limitations", paragraphs: [
                "Some question content is reproduced from your files as an image, because "
                + "it was drawn rather than written in the original. Such content cannot "
                + "be resized as text, read by a screen reader, or highlighted, and the "
                + "Operator cannot supply alternative text for material it does not "
                + "author.",
                "Highlighting works on Reading and Writing passages and on Math text "
                + "that contains no formulas. A Math paragraph with a formula in it, a "
                + "table, or a figure cannot be highlighted.",
                "Because the App reproduces the layout of a timed examination, some "
                + "screens are dense by design.",
                "Outside the test screen, most controls are named only by their visible "
                + "text, and the App's other screens have not been fully tested with a "
                + "screen reader or with the keyboard alone.",
            ]),
            Section(title: "Reporting Accessibility Problems", paragraphs: [
                "If you encounter an accessibility barrier in the App, please describe the "
                + "problem and where you encountered it and send that description to "
                + "\(contactEmail).",
                "The Operator will make reasonable efforts to address reported "
                + "accessibility problems.",
            ]),
            Section(title: "Good-Faith Statement", paragraphs: [
                "This Accessibility Statement is provided in good faith to describe the "
                + "Operator's ongoing efforts, and it is not a warranty of conformance "
                + "with any accessibility standard and is not an admission of any legal "
                + "obligation.",
            ]),
        ])

    static var plain: String {
        documents.map { document in
            "\(document.title)\nLast updated: \(lastUpdated).\n\n"
                + document.sections.map { "\($0.title)\n\n" + $0.paragraphs.joined(separator: "\n\n") }
                    .joined(separator: "\n\n")
        }.joined(separator: "\n\n\n")
    }
}
