from .i18n import L, Lf, Lp


def passages(subjects, has_grid_ins, timed, minutes):
    out = []

    if "reading_writing" in subjects:
        out.append((L("Reading and Writing"), [
            L("Each question is based on one or more passages, which may include "
              "a table or a graph. Read the passage and the question, then "
              "choose the best answer."),
            L("Every question has four choices and exactly one best answer."),
            L("You can highlight text in one of four colors and attach a note to it. "
              "Highlighting works on Reading and Writing passages and on Math text "
              "that contains no formulas. Highlights are kept with the question."),
        ]))

    if "math" in subjects:
        lines = [
            L("You may use a calculator on any question. This app does not "
              "provide one, so use whatever you will have on test day."),
            L("Reference — the formulas and figures the test provides — is in "
              "the toolbar and can be opened at any time."),
            L("Unless a question says otherwise: all variables and expressions "
              "stand for real numbers, figures are drawn to scale, every "
              "figure lies in a plane, and the domain of a function is every "
              "real number for which the function is real."),
        ]
        if has_grid_ins:
            lines.append(L("Some questions ask you to type the answer rather "
                           "than choose one. See \"Typing an answer\" below."))
        out.append((L("Math"), lines))

    if has_grid_ins:
        out.append((L("Typing an answer"), [
            L("Enter a fraction as 3/4, or its decimal as 0.75 — either counts. "
              "You do not have to reduce it."),
            L("A negative answer keeps its minus sign: −3/5 or −0.6."),
            L("A repeating decimal is right if you give enough of it: 2/3 can be "
              "entered as 2/3, .6666 or 0.667."),
            L("You can type up to 5 characters for a positive answer and 6 for a "
              "negative one; the minus sign counts."),
            L("Type a mixed number such as 3½ as 7/2 or 3.5. Typed as 3 1/2, it "
              "reads as 31/2 and is marked wrong."),
            L("Do not type a comma, units, a percent sign, or a dollar sign."),
        ]))

    out.append((L("Working through the section"), [
        Lp(minutes, "You have %d minute. The clock can be hidden, and it "
                    "comes back on its own with five minutes left.",
                    "You have %d minutes. The clock can be hidden, and it comes "
                    "back on its own with five minutes left.")
        if timed
        else L("There is no clock on this sitting. Take the time you need."),
        L("Mark for Review flags a question so you can find it again; the list "
          "at the foot of the screen jumps to any question."),
        L("Set aside keeps a question in a pile you can practice or export "
          "later. Unlike Mark for Review, it outlives this sitting."),
        L("The answer eliminator — ABC — crosses out choices you have ruled out."),
        L("A−/A+ resize the question, and so do Ctrl or Command with + and −."),
    ]))

    return out


def plain(subjects, has_grid_ins, timed, minutes):
    return "\n\n".join(
        heading + "\n\n" + "\n\n".join(lines)
        for heading, lines in passages(subjects, has_grid_ins, timed, minutes))


def _shape(session):
    return ({q.subject for q in session.questions},
            any(q.kind != "multiple_choice" for q in session.questions),
            bool(session.config.get("timed")),
            int(session.config.get("minutes", 0)))


def for_session(session):
    return passages(*_shape(session))


def for_session_text(session):
    return plain(*_shape(session))
