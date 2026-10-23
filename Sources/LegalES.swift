import Foundation

extension Legal {

    static var documentsES: [Document] { [privacyES, termsES, accessibilityES] }

    static let copyrightES = "\(operatorName) © 2026. Todos los derechos reservados."
    static let footprintES = "Sin afiliación con el College Board. "
        + "Todo se queda en tu computadora."

    private static let bilingualClauseES =
        "Este documento puede ofrecerse en más de un idioma; si las versiones "
        + "difieren en su significado, prevalece la versión en inglés."

    private static func contactES(_ subject: String) -> Section {
        Section(title: "Contáctanos", paragraphs: [
            "Si tienes preguntas sobre \(subject), puedes comunicarte con el "
            + "Operador en \(contactEmail).",
            bilingualClauseES,
        ])
    }

    static let privacyES = Document(
        title: "Política de Privacidad",
        summary: "Qué guarda la Aplicación, dónde lo guarda y por qué nada de ello llega hasta nosotros.",
        sections: [
            Section(title: "Alcance de esta Política", paragraphs: [
                "Esta Política de Privacidad explica qué información se recopila, se usa "
                + "y se conserva en relación con tu uso de \(Brand.appName) (la "
                + "\"Aplicación\"), operada por \(operatorName), una iniciativa educativa "
                + "independiente (el \"Operador\").",
                "Esta Política se aplica únicamente a la Aplicación, y no se aplica al "
                + "sitio web del Operador, al Banco de Preguntas del College Board ni a "
                + "ningún otro servicio del que puedas obtener material de preguntas, ni "
                + "a ningún otro sitio o servicio de terceros.",
                "Al usar la Aplicación, reconoces que has leído y entendido esta Política.",
            ]),
            Section(title: "La Aplicación no requiere una cuenta", paragraphs: [
                "La Aplicación no te exige registrarte, iniciar sesión ni crear ninguna "
                + "cuenta, y no cobra ni procesa ningún pago.",
            ]),
            Section(title: "La Aplicación funciona por completo en tu propio dispositivo",
                    paragraphs: [
                "La Aplicación no realiza conexiones de red de ningún tipo. No transmite "
                + "información alguna al Operador ni a ningún tercero, y no contiene "
                + "analítica, telemetría, publicidad ni reportes de fallos.",
                "Todo lo que la Aplicación guarda —los conjuntos de preguntas que "
                + "importas, los archivos PDF originales, tus respuestas, tu progreso e "
                + "historial de intentos, tus subrayados y notas, tus sesiones guardadas, "
                + "tus estantes y tus ajustes— se almacena únicamente en la carpeta "
                + "propia de la Aplicación en tu dispositivo.",
                "El Operador no recibe, transmite, recopila ni almacena nada de esta "
                + "información, y el Operador no tiene forma de verla, recuperarla ni "
                + "restaurarla si se pierde o se borra de tu dispositivo.",
                "Puedes abrir esa carpeta desde la propia Aplicación en cualquier momento "
                + "para inspeccionar, copiar, respaldar o eliminar su contenido.",
                "Eres responsable de proteger cualquier dispositivo en el que uses la "
                + "Aplicación, ya que la información almacenada localmente puede ser "
                + "vista por cualquiera que tenga acceso a ese dispositivo o a esa cuenta "
                + "de usuario.",
            ]),
            Section(title: "Varios estudiantes en una computadora", paragraphs: [
                "La Aplicación permite que más de un estudiante use la misma "
                + "computadora, cada uno con su propio progreso, estadísticas, notas, "
                + "mazos de tarjetas, idioma y ajustes. Los conjuntos de preguntas se "
                + "comparten entre ellos; todo lo personal se guarda por separado.",
                "Estos perfiles de estudiante son una comodidad, no una medida de "
                + "seguridad. **No están protegidos por una contraseña, un PIN ni ninguna "
                + "otra credencial, y cualquier persona que use la computadora puede "
                + "abrir cualquiera de ellos.** Existen para que dos estudiantes no se "
                + "sobrescriban el trabajo, no para mantener el trabajo de uno en "
                + "privado frente al otro.",
                "Si necesitas que tu trabajo sea privado frente a otras personas que usan "
                + "la misma computadora, usa una cuenta de usuario aparte del sistema "
                + "operativo, algo que la Aplicación no puede atravesar.",
                "Cuando dos estudiantes responden preguntas juntos en una misma sesión, "
                + "cada respuesta se registra únicamente al estudiante a quien le tocaba "
                + "el turno.",
            ]),
            Section(title: "Llevar tu trabajo a otro dispositivo", paragraphs: [
                "La Aplicación puede escribir todo lo personal de un estudiante en un "
                + "solo archivo, para poder moverlo a otra computadora. Crear ese "
                + "archivo, y elegir a dónde va, es enteramente tu decisión y tu acción.",
                "Una vez que has exportado ese archivo, es un archivo común en tu "
                + "dispositivo y ya no está protegido por la Aplicación. Si lo envías por "
                + "correo, lo copias a una unidad compartida o lo dejas en un disco "
                + "extraíble, cualquiera que lo obtenga puede leer los datos de estudio "
                + "que contiene. No está cifrado.",
                "Importa únicamente un archivo de estudiante que hayas creado tú mismo o "
                + "que hayas recibido de alguien en quien confías.",
            ]),
            Section(title: "Recordatorios", paragraphs: [
                "Si activas los recordatorios de estudio, la Aplicación le pide a tu "
                + "sistema operativo permiso para mostrar notificaciones y las programa "
                + "localmente en tu dispositivo. Ningún recordatorio se envía a través de "
                + "un servidor, y la Aplicación no se entera de si lo viste.",
            ]),
            Section(title: "Material que importas", paragraphs: [
                "La Aplicación no contiene contenido de preguntas propio. Todo el "
                + "material de práctica proviene de archivos PDF que tú mismo obtienes y "
                + "eliges importar.",
                "Los archivos importados se copian a la carpeta de la Aplicación en tu "
                + "dispositivo para poder leerlos de nuevo si el lector de la Aplicación "
                + "mejora. No se suben, ni se comparten, ni se transmiten a ningún lado.",
            ]),
            Section(title: "Sin venta ni intercambio de datos personales", paragraphs: [
                "El Operador no vende, alquila, intercambia ni comparte tus datos "
                + "personales con ningún tercero, porque la Aplicación no recopila ni "
                + "transmite dato personal alguno para empezar.",
            ]),
            Section(title: "Privacidad de menores", paragraphs: [
                "La Aplicación es un recurso educativo pensado para ser útil a "
                + "estudiantes que se preparan para el SAT y el PSAT, y el Operador "
                + "reconoce que muchos de sus usuarios serán menores de edad.",
                "La Aplicación no recopila conscientemente datos personales de usuarios "
                + "de ninguna edad, incluidos menores de 13 años, porque no recopila dato "
                + "personal alguno ni transmite nada desde tu dispositivo.",
                "El Operador anima a los menores a usar la Aplicación junto con un padre, "
                + "una madre, un tutor o un docente.",
            ]),
            Section(title: "Usuarios internacionales, Ucrania y la Unión Europea",
                    paragraphs: [
                "La Aplicación es usada por estudiantes en Ucrania, la Unión Europea, "
                + "Estados Unidos y otros países, y las leyes de protección de datos "
                + "difieren entre estas jurisdicciones.",
                "El Operador minimiza por diseño los datos personales que recopila, ya "
                + "que la Aplicación almacena datos únicamente en tu propio dispositivo y "
                + "el Operador no recibe ninguno.",
                "Como todos los datos asociados a tu uso de la Aplicación permanecen en "
                + "tu propio dispositivo, puedes ejercer control completo sobre ellos en "
                + "cualquier momento eliminándolos de la carpeta de la Aplicación.",
            ]),
            Section(title: "Seguridad", paragraphs: [
                "Como la Aplicación no transmite nada, la seguridad de tu información "
                + "depende de la seguridad del dispositivo en el que está almacenada.",
                "Ningún método de almacenamiento electrónico es completamente seguro, y "
                + "el Operador no puede garantizar una seguridad absoluta.",
            ]),
            Section(title: "Cambios a esta Política", paragraphs: [
                "El Operador puede actualizar esta Política de vez en cuando para "
                + "reflejar cambios en la Aplicación o por razones legales u operativas.",
                "La fecha que aparece con esta Política indica cuándo fue revisada por "
                + "última vez, y el uso continuado de la Aplicación después de una "
                + "actualización constituye tu aceptación de la Política revisada.",
            ]),
            contactES("esta Política de Privacidad o sobre cómo se maneja tu información"),
        ])

    static let termsES = Document(
        title: "Términos del Servicio",
        summary: "Para qué sirve la Aplicación, qué no promete y los límites de nuestra responsabilidad.",
        sections: [
            Section(title: "Aceptación de estos Términos", paragraphs: [
                "Estos Términos del Servicio (los \"Términos\") rigen tu acceso y uso de "
                + "\(Brand.appName) (la \"Aplicación\"), operada por \(operatorName), una "
                + "iniciativa educativa independiente (el \"Operador\").",
                "Al instalar o usar la Aplicación, aceptas quedar sujeto a estos "
                + "Términos, y si no estás de acuerdo con ellos, no debes usar la "
                + "Aplicación.",
                "Si eres menor de edad, el Operador recomienda que revises estos Términos "
                + "junto con un padre, una madre, un tutor o un docente antes de usar la "
                + "Aplicación.",
            ]),
            Section(title: "Sin afiliación con el College Board", paragraphs: [
                "SAT® es una marca registrada del College Board. PSAT/NMSQT® es una marca "
                + "registrada del College Board y de la National Merit Scholarship "
                + "Corporation. PSAT™ 10 y PSAT™ 8/9 son marcas del College Board. "
                + "Bluebook™ es la propia aplicación de examen del College Board.",
                "Ni el College Board ni la National Merit Scholarship Corporation están "
                + "afiliados con la Aplicación o el Operador, ni los patrocinan, "
                + "respaldan, licencian o han revisado. Estos nombres se usan únicamente "
                + "para identificar los exámenes para los que la Aplicación pretende "
                + "ayudarte a practicar, y dicho uso es nominativo.",
                "La Aplicación se parece deliberadamente a la aplicación de examen del "
                + "College Board en disposición y comportamiento, para que el formato no "
                + "guarde sorpresas el día del examen. La Aplicación no es esa "
                + "aplicación, no está conectada con ella y no puede usarse para "
                + "presentar ni inscribirse en ningún examen real.",
            ]),
            Section(title: "La Aplicación ofrece solo material de práctica", paragraphs: [
                "La Aplicación se ofrece únicamente con fines educativos y de práctica "
                + "generales, para ayudar a los estudiantes a ensayar el formato y el "
                + "ritmo del SAT y el PSAT digitales.",
                "Nada en la Aplicación constituye preparación acreditada para exámenes, "
                + "asesoría de admisiones ni asesoramiento profesional de ningún tipo, y "
                + "tu uso de la Aplicación no crea ninguna relación de asesor-cliente.",
            ]),
            Section(title: "El material de preguntas es tuyo, no del Operador",
                    paragraphs: [
                "La Aplicación se distribuye sin contenido de preguntas. Todo el material "
                + "de práctica proviene de archivos que tú mismo obtienes e importas.",
                "El material de preguntas, incluidos su texto, sus figuras y sus "
                + "explicaciones, sigue siendo propiedad de su respectivo titular. El "
                + "Operador no reclama derecho alguno sobre él, no lo distribuye y no lo "
                + "transmite a ningún lado.",
                "Eres responsable de obtener lícitamente cualquier material que importes y "
                + "de cumplir con los términos bajo los cuales lo obtuviste, incluida "
                + "cualquier restricción sobre compartirlo con otras personas.",
            ]),
            Section(title: "Sin garantía de ningún resultado", paragraphs: [
                "Nada en la Aplicación garantiza ni implica ningún resultado en "
                + "particular, incluido ningún puntaje de examen, la admisión a ninguna "
                + "institución educativa, ni la obtención de ninguna beca o ayuda "
                + "financiera.",
                "La Aplicación no produce un puntaje escalado del SAT ni del PSAT, y "
                + "ningún resultado, porcentaje o estadística que muestre debe "
                + "interpretarse como tal ni usarse para predecirlo.",
                "Cuando la Aplicación reproduce la estructura del examen digital, "
                + "incluidas la extensión de los módulos, los tiempos y el encaminamiento "
                + "de un segundo módulo adaptativo, lo hace como una aproximación al "
                + "formato publicado. El umbral que la Aplicación usa para encaminar "
                + "entre un segundo módulo más fácil y uno más difícil es propio del "
                + "Operador, porque el College Board no publica sus propios criterios, y "
                + "no debe entenderse como una reproducción de estos.",
            ]),
            Section(title: "El material importado lo lee un programa", paragraphs: [
                "La Aplicación lee automáticamente el material de preguntas de tus "
                + "archivos. Este proceso está probado, pero no es infalible, y "
                + "ocasionalmente puede leer mal un texto, una respuesta, una tabla o una "
                + "figura.",
                "Debes verificar contra tu archivo original cualquier cosa que parezca "
                + "incorrecta antes de concluir que tu respuesta estuvo mal, y no debes "
                + "confiar en la Aplicación como registro autorizado de ninguna pregunta "
                + "ni respuesta.",
            ]),
            Section(title: "Uso aceptable", paragraphs: [
                "Aceptas usar la Aplicación únicamente con fines lícitos y de manera "
                + "coherente con estos Términos.",
                "Aceptas no usar la Aplicación para reproducir, redistribuir o poner a "
                + "disposición material de preguntas a ninguna persona que no tenga "
                + "derecho a recibirlo.",
                "Aceptas no usar la Aplicación con ningún fin ilícito ni en violación de "
                + "ninguna ley o reglamento local, estatal, nacional o internacional "
                + "aplicable.",
            ]),
            Section(title: "Propiedad intelectual", paragraphs: [
                "El software, el diseño, los textos y el arte de la Aplicación, incluidos "
                + "el nombre, el sello y el logotipo del Operador, son propiedad del "
                + "Operador o de sus licenciantes y están protegidos por las leyes de "
                + "derechos de autor, marcas y otras leyes de propiedad intelectual. Esto "
                + "no se extiende al material de preguntas que importas, tratado más "
                + "arriba.",
                "El Operador te concede una licencia limitada, revocable, no exclusiva y "
                + "no transferible para usar la Aplicación con fines educativos "
                + "personales y no comerciales.",
                "No puedes vender la Aplicación, ofrecerla como un servicio de pago ni "
                + "presentarla como propia o como producto de otra organización.",
            ]),
            Section(title: "Esta es una versión de prueba", paragraphs: [
                "Esta versión de la Aplicación es una beta: una versión de prueba, "
                + "señalada como tal junto al nombre de la Aplicación. Se ofrece para que "
                + "los estudiantes puedan probarla e informar problemas, y puede contener "
                + "defectos que una versión terminada no tendría.",
                "Tu trabajo se guarda de la manera habitual y no se trata de forma "
                + "distinta por ser esta una versión de prueba. Aun así, mientras la "
                + "Aplicación esté en beta se te recomienda encarecidamente guardar tu "
                + "propia copia de todo lo que no quieras perder; la Aplicación puede "
                + "escribir todo lo tuyo en un solo archivo precisamente para eso.",
                "Las exenciones y limitaciones que siguen se aplican por completo a una "
                + "versión de prueba.",
            ]),
            Section(title: "Exención de garantías", paragraphs: [
                "La Aplicación se ofrece \"tal cual\" y \"según disponibilidad\", sin "
                + "garantías de ningún tipo, ya sean expresas, implícitas o legales.",
                "En la máxima medida permitida por la ley aplicable, el Operador rechaza "
                + "toda garantía, incluidas las garantías implícitas de comerciabilidad, "
                + "idoneidad para un fin determinado, no infracción, exactitud y "
                + "funcionamiento ininterrumpido o libre de errores.",
                "El Operador no garantiza que la Aplicación esté libre de errores o "
                + "defectos, que cualquier error o defecto vaya a corregirse, ni que la "
                + "Aplicación lea correcta o completamente ningún archivo en particular.",
            ]),
            Section(title: "Limitación de responsabilidad", paragraphs: [
                "En la máxima medida permitida por la ley aplicable, el Operador no será "
                + "responsable de ningún daño directo, indirecto, incidental, especial, "
                + "consecuente o punitivo que surja de, o esté relacionado de cualquier "
                + "manera con, tu uso o imposibilidad de uso de la Aplicación.",
                "Esta limitación se aplica a cualquier decisión que tomes o acción que "
                + "emprendas confiando en la Aplicación o en cualquier resultado que "
                + "muestre, y a cualquier pérdida de datos almacenados por la Aplicación, "
                + "incluidos conjuntos de preguntas, progreso, notas o archivos "
                + "importados.",
                "Esta limitación se aplica sin importar la teoría jurídica en la que se "
                + "base una reclamación, ya sea contrato, responsabilidad extracontractual, "
                + "negligencia, responsabilidad objetiva u otra, e incluso si se advirtió "
                + "al Operador de la posibilidad de tales daños.",
                "Como la Aplicación se ofrece de forma gratuita, y como algunas "
                + "jurisdicciones no permiten ciertas limitaciones de responsabilidad, "
                + "puede que algunas de las limitaciones de esta sección no se te "
                + "apliquen, y en tales casos la responsabilidad del Operador se limitará "
                + "en la mayor medida permitida por la ley aplicable.",
            ]),
            Section(title: "Indemnización", paragraphs: [
                "Aceptas indemnizar, defender y mantener indemne al Operador, a sus "
                + "directivos, colaboradores y agentes frente a cualquier reclamación, "
                + "responsabilidad, daño, pérdida y gasto, incluidos honorarios "
                + "razonables de abogados, que surjan de, o estén relacionados de "
                + "cualquier manera con, tu uso indebido de la Aplicación, tu "
                + "incumplimiento de estos Términos o tu manejo de cualquier material que "
                + "importes.",
            ]),
            Section(title: "Ley aplicable", paragraphs: [
                "Estos Términos se rigen por las leyes del Estado de \(governingState), "
                + "sin atender a sus principios sobre conflicto de leyes.",
            ]),
            Section(title: "Cambios a estos Términos", paragraphs: [
                "El Operador puede revisar estos Términos de vez en cuando, y la fecha "
                + "que aparece con ellos indica cuándo fueron revisados por última vez.",
                "Tu uso continuado de la Aplicación tras cualquier revisión constituye tu "
                + "aceptación de los Términos revisados.",
            ]),
            contactES("estos Términos"),
        ])

    static let accessibilityES = Document(
        title: "Declaración de Accesibilidad",
        summary: "Qué hace la Aplicación para seguir siendo usable, y dónde se queda corta.",
        sections: [
            Section(title: "Nuestro compromiso", paragraphs: [
                "El Operador se compromete a que \(Brand.appName) sea usable por la mayor "
                + "cantidad posible de estudiantes, incluidos los estudiantes con "
                + "discapacidad.",
            ]),
            Section(title: "Medidas que hemos tomado", paragraphs: [
                "El texto de las preguntas puede redimensionarse en cualquier momento con "
                + "los controles A− y A+ o con las teclas Control y Command junto con más "
                + "y menos, y el tamaño elegido se aplica a todas las preguntas y también "
                + "a las figuras representadas.",
                "En macOS la Aplicación respeta el ajuste de Reducir Movimiento del "
                + "sistema, y en Windows respeta el ajuste de efectos de animación del "
                + "sistema. Linux no tiene un único ajuste de este tipo, así que allí la "
                + "Aplicación se basa en el suyo propio. En todas las plataformas ofrece "
                + "además su propio ajuste para reducir el movimiento con independencia "
                + "del sistema.",
                "La Aplicación ofrece un tema claro y uno oscuro, y las superficies que "
                + "muestran el contenido de las preguntas se mantienen deliberadamente en "
                + "una única apariencia de alto contraste en ambos, para que el material "
                + "reproducido de tus archivos siga siendo legible.",
                "Un Modo Sigiloso aparte dibuja toda la Aplicación, incluidas esas "
                + "superficies, sobre negro e invierte las figuras representadas, para "
                + "estudiantes que estudian de noche o a quienes una pantalla brillante "
                + "les resulta incómoda. También silencia los propios recordatorios de la "
                + "Aplicación.",
                "Durante un examen, los controles que necesita el estudiante —las "
                + "opciones de respuesta, los botones para retroceder y avanzar, la marca "
                + "para revisar, la lista de preguntas, el cronómetro, los controles de "
                + "tamaño del texto, la hoja de referencia, el resaltador y el eliminador "
                + "de respuestas— tienen nombres que anuncian los lectores de pantalla, y "
                + "se puede elegir una respuesta con la tecla de su letra y cambiar de "
                + "pregunta con las teclas de flecha.",
            ]),
            Section(title: "Limitaciones conocidas", paragraphs: [
                "Parte del contenido de las preguntas se reproduce de tus archivos como "
                + "imagen, porque en el original estaba dibujado en lugar de escrito. Ese "
                + "contenido no puede redimensionarse como texto, ni leerse con un lector "
                + "de pantalla, ni subrayarse, y el Operador no puede aportar texto "
                + "alternativo para material del que no es autor.",
                "El resaltado funciona en los textos de Lectura y Redacción y en el texto "
                + "de Matemáticas que no contiene fórmulas. No se puede resaltar un párrafo "
                + "de Matemáticas que contenga una fórmula, ni una tabla, ni una figura.",
                "Como la Aplicación reproduce la disposición de un examen cronometrado, "
                + "algunas pantallas son densas por diseño.",
                "Fuera de la pantalla del examen, la mayoría de los controles solo se "
                + "nombran por su texto visible, y las demás pantallas de la Aplicación no "
                + "se han probado a fondo con un lector de pantalla ni solo con el teclado.",
            ]),
            Section(title: "Informar de problemas de accesibilidad", paragraphs: [
                "Si encuentras una barrera de accesibilidad en la Aplicación, describe "
                + "por favor el problema y dónde lo encontraste, y envía esa descripción "
                + "a \(contactEmail).",
                "El Operador toma en serio estos informes y los usa para decidir qué "
                + "corregir a continuación.",
            ]),
            contactES("esta Declaración de Accesibilidad"),
        ])
}
