import Foundation

extension Legal {

    static var documentsPT: [Document] { [privacyPT, termsPT, accessibilityPT] }

    static let copyrightPT = "\(operatorName) © 2026. Todos os direitos reservados."
    static let footprintPT = "Sem afiliação com o College Board. "
        + "Tudo fica no seu computador."

    private static let bilingualClausePT =
        "Este documento pode ser fornecido em mais de um idioma; se as versões "
        + "divergirem em significado, prevalece a versão em inglês."

    private static func contactPT(_ subject: String) -> Section {
        Section(title: "Fale conosco", paragraphs: [
            "Se você tiver dúvidas sobre \(subject), pode entrar em contato com o "
            + "Operador em \(contactEmail).",
            bilingualClausePT,
        ])
    }

    static let privacyPT = Document(
        title: "Política de Privacidade",
        summary: "O que o Aplicativo guarda, onde guarda e por que nada disso chega até nós.",
        sections: [
            Section(title: "Escopo desta Política", paragraphs: [
                "Esta Política de Privacidade explica quais informações são coletadas, "
                + "usadas e mantidas em relação ao seu uso do \(Brand.appName) (o "
                + "\"Aplicativo\"), operado pela \(operatorName), uma iniciativa "
                + "educacional independente (o \"Operador\").",
                "Esta Política se aplica somente ao Aplicativo e não se aplica ao site do "
                + "Operador, ao Banco de Questões do College Board ou a qualquer outro "
                + "serviço do qual você possa obter material de questões, nem a qualquer "
                + "outro site ou serviço de terceiros.",
                "Ao usar o Aplicativo, você reconhece que leu e entendeu esta Política.",
            ]),
            Section(title: "O Aplicativo não exige conta", paragraphs: [
                "O Aplicativo não exige que você se cadastre, faça login ou crie qualquer "
                + "conta, e não cobra nem processa nenhum pagamento.",
            ]),
            Section(title: "O Aplicativo funciona inteiramente no seu dispositivo",
                    paragraphs: [
                "O Aplicativo não faz conexões de rede de nenhum tipo. Ele não transmite "
                + "informação alguma ao Operador nem a terceiros, e não contém análise de "
                + "uso, telemetria, publicidade ou relatórios de falhas.",
                "Tudo o que o Aplicativo guarda — os conjuntos de questões que você "
                + "importa, os arquivos PDF originais, suas respostas, seu progresso e "
                + "histórico de tentativas, seus destaques e anotações, suas sessões "
                + "salvas, suas prateleiras e seus ajustes — fica armazenado apenas na "
                + "pasta do próprio Aplicativo no seu dispositivo.",
                "O Operador não recebe, transmite, coleta nem armazena nada dessas "
                + "informações, e o Operador não tem como visualizá-las, recuperá-las ou "
                + "restaurá-las se forem perdidas ou apagadas do seu dispositivo.",
                "Você pode abrir essa pasta pelo próprio Aplicativo a qualquer momento "
                + "para inspecionar, copiar, fazer backup ou excluir o seu conteúdo.",
                "Você é responsável por proteger qualquer dispositivo em que usar o "
                + "Aplicativo, já que informações armazenadas localmente podem ser vistas "
                + "por qualquer pessoa com acesso a esse dispositivo ou a essa conta de "
                + "usuário.",
            ]),
            Section(title: "Vários estudantes em um computador", paragraphs: [
                "O Aplicativo permite que mais de um estudante use o mesmo computador, "
                + "cada um com o seu próprio progresso, estatísticas, anotações, baralhos "
                + "de cartões, idioma e ajustes. Os conjuntos de questões são "
                + "compartilhados entre eles; tudo o que é pessoal fica guardado "
                + "separadamente.",
                "Esses perfis de estudante são uma conveniência, não uma medida de "
                + "segurança. **Eles não são protegidos por senha, PIN ou qualquer outra "
                + "credencial, e qualquer pessoa que use o computador pode abrir qualquer "
                + "um deles.** Eles existem para que dois estudantes não sobrescrevam o "
                + "trabalho um do outro, e não para manter o trabalho de um em sigilo "
                + "diante do outro.",
                "Se você precisa que o seu trabalho seja privado em relação a outras "
                + "pessoas que usam o mesmo computador, use uma conta de usuário separada "
                + "do sistema operacional, algo que o Aplicativo não consegue atravessar.",
                "Quando dois estudantes respondem questões juntos na mesma sessão, cada "
                + "resposta é registrada somente para o estudante de quem era a vez.",
            ]),
            Section(title: "Levar o seu trabalho para outro dispositivo", paragraphs: [
                "O Aplicativo pode gravar tudo o que é pessoal de um estudante em um "
                + "único arquivo, para que possa ser movido para outro computador. Criar "
                + "esse arquivo, e escolher para onde ele vai, é inteiramente decisão sua "
                + "e ação sua.",
                "Depois de exportado, esse arquivo é um arquivo comum no seu dispositivo "
                + "e não está mais protegido pelo Aplicativo. Se você enviá-lo por "
                + "e-mail, copiá-lo para um disco compartilhado ou deixá-lo em uma mídia "
                + "removível, qualquer pessoa que o obtiver poderá ler os dados de estudo "
                + "que ele contém. Ele não é criptografado.",
                "Importe apenas um arquivo de estudante que você mesmo criou ou que "
                + "recebeu de alguém em quem confia.",
            ]),
            Section(title: "Lembretes", paragraphs: [
                "Se você ativar os lembretes de estudo, o Aplicativo pede ao seu sistema "
                + "operacional permissão para mostrar notificações e as agenda localmente "
                + "no seu dispositivo. Nenhum lembrete é enviado por meio de servidor, e o "
                + "Aplicativo não fica sabendo se você o viu.",
            ]),
            Section(title: "Material que você importa", paragraphs: [
                "O Aplicativo não contém conteúdo de questões próprio. Todo o material de "
                + "prática vem de arquivos PDF que você mesmo obtém e escolhe importar.",
                "Os arquivos importados são copiados para a pasta do Aplicativo no seu "
                + "dispositivo para que possam ser lidos de novo caso o leitor do "
                + "Aplicativo melhore. Eles não são enviados, compartilhados nem "
                + "transmitidos para lugar algum.",
            ]),
            Section(title: "Sem venda ou compartilhamento de dados pessoais",
                    paragraphs: [
                "O Operador não vende, aluga, troca nem compartilha os seus dados "
                + "pessoais com terceiros, porque o Aplicativo não coleta nem transmite "
                + "dado pessoal algum, para começar.",
            ]),
            Section(title: "Privacidade de menores", paragraphs: [
                "O Aplicativo é um recurso educacional pensado para ser útil a estudantes "
                + "que se preparam para o SAT e o PSAT, e o Operador reconhece que muitos "
                + "de seus usuários serão menores de idade.",
                "O Aplicativo não coleta conscientemente dados pessoais de usuários de "
                + "qualquer idade, incluindo crianças menores de 13 anos, porque não "
                + "coleta dado pessoal algum e não transmite nada do seu dispositivo.",
                "O Operador incentiva menores a usar o Aplicativo junto com um pai, uma "
                + "mãe, um responsável ou um professor.",
            ]),
            Section(title: "Usuários internacionais, Ucrânia e União Europeia",
                    paragraphs: [
                "O Aplicativo é usado por estudantes na Ucrânia, na União Europeia, nos "
                + "Estados Unidos e em outros países, e as leis de proteção de dados "
                + "diferem entre essas jurisdições.",
                "O Operador minimiza por concepção os dados pessoais que coleta, já que o "
                + "Aplicativo armazena dados somente no seu próprio dispositivo e o "
                + "Operador não recebe nenhum deles.",
                "Como todos os dados associados ao seu uso do Aplicativo permanecem no seu "
                + "próprio dispositivo, você pode exercer controle completo sobre eles a "
                + "qualquer momento, excluindo-os da pasta do Aplicativo.",
            ]),
            Section(title: "Segurança", paragraphs: [
                "Como o Aplicativo não transmite nada, a segurança das suas informações "
                + "depende da segurança do dispositivo em que elas estão armazenadas.",
                "Nenhum método de armazenamento eletrônico é completamente seguro, e o "
                + "Operador não pode garantir segurança absoluta.",
            ]),
            Section(title: "Alterações nesta Política", paragraphs: [
                "O Operador pode atualizar esta Política de tempos em tempos para "
                + "refletir mudanças no Aplicativo ou por razões legais ou operacionais.",
                "A data exibida com esta Política indica quando ela foi revisada pela "
                + "última vez, e o uso continuado do Aplicativo após uma atualização "
                + "constitui a sua aceitação da Política revisada.",
            ]),
            contactPT("esta Política de Privacidade ou sobre como as suas informações são tratadas"),
        ])

    static let termsPT = Document(
        title: "Termos de Serviço",
        summary: "Para que serve o Aplicativo, o que ele não promete e os limites da nossa responsabilidade.",
        sections: [
            Section(title: "Aceitação destes Termos", paragraphs: [
                "Estes Termos de Serviço (os \"Termos\") regem o seu acesso e uso do "
                + "\(Brand.appName) (o \"Aplicativo\"), operado pela \(operatorName), uma "
                + "iniciativa educacional independente (o \"Operador\").",
                "Ao instalar ou usar o Aplicativo, você concorda em se vincular a estes "
                + "Termos e, se não concordar com eles, não deve usar o Aplicativo.",
                "Se você for menor de idade, o Operador recomenda que revise estes Termos "
                + "junto com um pai, uma mãe, um responsável ou um professor antes de usar "
                + "o Aplicativo.",
            ]),
            Section(title: "Sem afiliação com o College Board", paragraphs: [
                "SAT® é uma marca registrada do College Board. PSAT/NMSQT® é uma marca "
                + "registrada do College Board e da National Merit Scholarship "
                + "Corporation. PSAT™ 10 e PSAT™ 8/9 são marcas do College Board. "
                + "Bluebook™ é o próprio aplicativo de prova do College Board.",
                "Nem o College Board nem a National Merit Scholarship Corporation são "
                + "afiliados ao Aplicativo ou ao Operador, nem os patrocinam, endossam, "
                + "licenciam ou revisaram. Esses nomes são usados somente para "
                + "identificar os exames para os quais o Aplicativo pretende ajudar você "
                + "a praticar, e tal uso é nominativo.",
                "O Aplicativo se parece deliberadamente com o aplicativo de prova do "
                + "College Board em disposição e comportamento, para que o formato não "
                + "traga surpresas no dia da prova. O Aplicativo não é aquele aplicativo, "
                + "não está conectado a ele e não pode ser usado para fazer nem para se "
                + "inscrever em nenhum exame real.",
            ]),
            Section(title: "O Aplicativo oferece apenas material de prática", paragraphs: [
                "O Aplicativo é fornecido exclusivamente para fins educacionais e de "
                + "prática gerais, para ajudar estudantes a ensaiar o formato e o ritmo do "
                + "SAT e do PSAT digitais.",
                "Nada no Aplicativo constitui preparação credenciada para exames, "
                + "orientação de admissões ou aconselhamento profissional de qualquer "
                + "tipo, e o seu uso do Aplicativo não cria nenhuma relação de "
                + "consultor-cliente.",
            ]),
            Section(title: "O material de questões é seu, não do Operador", paragraphs: [
                "O Aplicativo é distribuído sem conteúdo de questões. Todo o material de "
                + "prática vem de arquivos que você mesmo obtém e importa.",
                "O material de questões, incluindo o seu texto, as suas figuras e as suas "
                + "explicações, continua sendo propriedade do respectivo titular. O "
                + "Operador não reivindica direito algum sobre ele, não o distribui e não "
                + "o transmite para lugar nenhum.",
                "Você é responsável por obter licitamente qualquer material que importar e "
                + "por cumprir os termos sob os quais o obteve, incluindo qualquer "
                + "restrição quanto a compartilhá-lo com outras pessoas.",
            ]),
            Section(title: "Sem garantia de qualquer resultado", paragraphs: [
                "Nada no Aplicativo garante ou dá a entender qualquer resultado "
                + "específico, incluindo qualquer nota de prova, admissão em qualquer "
                + "instituição de ensino ou obtenção de qualquer bolsa ou auxílio "
                + "financeiro.",
                "O Aplicativo não produz uma nota escalada do SAT ou do PSAT, e nenhum "
                + "resultado, porcentagem ou estatística que ele exiba deve ser "
                + "interpretado como tal nem usado para prevê-la.",
                "Quando o Aplicativo reproduz a estrutura da prova digital, incluindo a "
                + "extensão dos módulos, os tempos e o encaminhamento de um segundo módulo "
                + "adaptativo, ele o faz como uma aproximação do formato publicado. O "
                + "limiar que o Aplicativo usa para encaminhar entre um segundo módulo "
                + "mais fácil e um mais difícil é do próprio Operador, porque o College "
                + "Board não publica os seus próprios critérios, e não deve ser entendido "
                + "como uma reprodução deles.",
            ]),
            Section(title: "O material importado é lido por um programa", paragraphs: [
                "O Aplicativo lê automaticamente o material de questões dos seus "
                + "arquivos. Esse processo é testado, mas não é infalível, e pode "
                + "ocasionalmente ler errado um texto, uma resposta, uma tabela ou uma "
                + "figura.",
                "Você deve verificar no seu arquivo original qualquer coisa que pareça "
                + "incorreta antes de concluir que a sua resposta estava errada, e não "
                + "deve confiar no Aplicativo como registro oficial de qualquer questão "
                + "ou resposta.",
            ]),
            Section(title: "Uso aceitável", paragraphs: [
                "Você concorda em usar o Aplicativo apenas para fins lícitos e de maneira "
                + "coerente com estes Termos.",
                "Você concorda em não usar o Aplicativo para reproduzir, redistribuir ou "
                + "disponibilizar material de questões a qualquer pessoa que não tenha "
                + "direito a recebê-lo.",
                "Você concorda em não usar o Aplicativo para qualquer finalidade ilícita "
                + "ou em violação de qualquer lei ou regulamento local, estadual, nacional "
                + "ou internacional aplicável.",
            ]),
            Section(title: "Propriedade intelectual", paragraphs: [
                "O software, o design, os textos e a arte do Aplicativo, incluindo o nome, "
                + "o selo e a marca nominativa do Operador, são propriedade do Operador ou "
                + "de seus licenciadores e são protegidos por leis de direitos autorais, "
                + "marcas e outras leis de propriedade intelectual. Isso não se estende ao "
                + "material de questões que você importa, tratado acima.",
                "O Operador concede a você uma licença limitada, revogável, não exclusiva "
                + "e intransferível para usar o Aplicativo para os seus próprios fins "
                + "educacionais, pessoais e não comerciais.",
                "Você não pode vender o Aplicativo, oferecê-lo como serviço pago nem "
                + "apresentá-lo como seu ou como produto de outra organização.",
            ]),
            Section(title: "Esta é uma versão de teste", paragraphs: [
                "Esta versão do Aplicativo é uma beta: uma versão de teste, marcada como "
                + "tal ao lado do nome do Aplicativo. Ela é oferecida para que estudantes "
                + "possam experimentá-la e relatar problemas, e pode conter defeitos que "
                + "uma versão finalizada não teria.",
                "O seu trabalho é salvo da maneira habitual e não é tratado de forma "
                + "diferente por esta ser uma versão de teste. Ainda assim, enquanto o "
                + "Aplicativo estiver em beta, recomendamos fortemente que você mantenha "
                + "a sua própria cópia de tudo o que não queira perder; o Aplicativo pode "
                + "gravar tudo o que é seu em um único arquivo exatamente para isso.",
                "As isenções e limitações abaixo se aplicam integralmente a uma versão de "
                + "teste.",
            ]),
            Section(title: "Isenção de garantias", paragraphs: [
                "O Aplicativo é fornecido \"no estado em que se encontra\" e \"conforme "
                + "disponibilidade\", sem garantias de qualquer tipo, sejam expressas, "
                + "implícitas ou legais.",
                "Na máxima extensão permitida pela lei aplicável, o Operador se isenta de "
                + "todas as garantias, incluindo garantias implícitas de "
                + "comercialização, adequação a uma finalidade específica, não violação, "
                + "exatidão e funcionamento ininterrupto ou livre de erros.",
                "O Operador não garante que o Aplicativo estará livre de erros ou "
                + "defeitos, que qualquer erro ou defeito será corrigido, nem que o "
                + "Aplicativo lerá corretamente ou integralmente qualquer arquivo "
                + "específico.",
            ]),
            Section(title: "Limitação de responsabilidade", paragraphs: [
                "Na máxima extensão permitida pela lei aplicável, o Operador não será "
                + "responsável por quaisquer danos diretos, indiretos, incidentais, "
                + "especiais, consequentes ou punitivos decorrentes de, ou de qualquer "
                + "forma relacionados a, seu uso ou impossibilidade de uso do Aplicativo.",
                "Esta limitação se aplica a qualquer decisão que você tome ou ação que "
                + "empreenda confiando no Aplicativo ou em qualquer resultado que ele "
                + "exiba, e a qualquer perda de dados armazenados pelo Aplicativo, "
                + "incluindo conjuntos de questões, progresso, anotações ou arquivos "
                + "importados.",
                "Esta limitação se aplica independentemente da teoria jurídica em que uma "
                + "reivindicação se baseie, seja contrato, ato ilícito, negligência, "
                + "responsabilidade objetiva ou outra, e mesmo que o Operador tenha sido "
                + "avisado da possibilidade de tais danos.",
                "Como o Aplicativo é oferecido gratuitamente, e como algumas jurisdições "
                + "não permitem certas limitações de responsabilidade, algumas das "
                + "limitações desta seção podem não se aplicar a você e, nesses casos, a "
                + "responsabilidade do Operador será limitada na maior extensão permitida "
                + "pela lei aplicável.",
            ]),
            Section(title: "Indenização", paragraphs: [
                "Você concorda em indenizar, defender e isentar de responsabilidade o "
                + "Operador, seus dirigentes, colaboradores e agentes de e contra "
                + "quaisquer reivindicações, responsabilidades, danos, perdas e despesas, "
                + "incluindo honorários advocatícios razoáveis, decorrentes de, ou de "
                + "qualquer forma relacionados a, seu uso indevido do Aplicativo, sua "
                + "violação destes Termos ou seu manuseio de qualquer material que você "
                + "importar.",
            ]),
            Section(title: "Lei aplicável", paragraphs: [
                "Estes Termos são regidos pelas leis do Estado de \(governingState), sem "
                + "considerar os seus princípios de conflito de leis.",
            ]),
            Section(title: "Alterações nestes Termos", paragraphs: [
                "O Operador pode revisar estes Termos de tempos em tempos, e a data "
                + "exibida com eles indica quando foram revisados pela última vez.",
                "O seu uso continuado do Aplicativo após qualquer revisão constitui a sua "
                + "aceitação dos Termos revisados.",
            ]),
            contactPT("estes Termos"),
        ])

    static let accessibilityPT = Document(
        title: "Declaração de Acessibilidade",
        summary: "O que o Aplicativo faz para continuar utilizável, e onde ele fica devendo.",
        sections: [
            Section(title: "Nosso compromisso", paragraphs: [
                "O Operador tem o compromisso de tornar o \(Brand.appName) utilizável pelo "
                + "maior número possível de estudantes, incluindo estudantes com "
                + "deficiência.",
            ]),
            Section(title: "Medidas que tomamos", paragraphs: [
                "O texto das questões pode ser redimensionado a qualquer momento com os "
                + "controles A− e A+ ou com as teclas Control e Command junto com mais e "
                + "menos, e o tamanho escolhido se aplica a todas as questões e também às "
                + "figuras renderizadas.",
                "No macOS o Aplicativo respeita o ajuste Reduzir Movimento do sistema, e "
                + "no Windows respeita o ajuste de efeitos de animação do sistema. O Linux "
                + "não tem um único ajuste desse tipo, então ali o Aplicativo depende do "
                + "seu próprio. Em todas as plataformas ele também oferece o seu próprio "
                + "ajuste para reduzir o movimento independentemente do sistema.",
                "O Aplicativo oferece um tema claro e um escuro, e as superfícies que "
                + "exibem o conteúdo das questões são mantidas deliberadamente em uma "
                + "única aparência de alto contraste em ambos, para que o material "
                + "reproduzido dos seus arquivos continue legível.",
                "Um Modo Furtivo à parte desenha o Aplicativo inteiro, inclusive essas "
                + "superfícies, sobre preto e inverte as figuras renderizadas, para "
                + "estudantes que estudam à noite ou para quem uma tela clara é "
                + "desconfortável. Ele também silencia os lembretes do próprio "
                + "Aplicativo.",
                "Durante uma prova, os controles de que o estudante precisa — as opções "
                + "de resposta, os botões para voltar e avançar, a marcação para revisão, "
                + "a lista de questões, o cronômetro, os controles de tamanho do texto, a "
                + "folha de referência, o marcador de texto e o eliminador de respostas — "
                + "têm nomes anunciados pelos leitores de tela, e é possível escolher uma "
                + "resposta com a tecla da sua letra e mudar de questão com as teclas de "
                + "seta.",
            ]),
            Section(title: "Limitações conhecidas", paragraphs: [
                "Parte do conteúdo das questões é reproduzida dos seus arquivos como "
                + "imagem, porque no original foi desenhada em vez de escrita. Esse "
                + "conteúdo não pode ser redimensionado como texto, nem lido por um "
                + "leitor de tela, nem destacado, e o Operador não pode fornecer texto "
                + "alternativo para material do qual não é autor.",
                "O destaque funciona nos textos de Leitura e Escrita e no texto de "
                + "Matemática que não contém fórmulas. Não é possível destacar um parágrafo "
                + "de Matemática que contenha uma fórmula, nem uma tabela, nem uma figura.",
                "Como o Aplicativo reproduz a disposição de uma prova cronometrada, "
                + "algumas telas são densas por concepção.",
                "Fora da tela da prova, a maioria dos controles é nomeada apenas pelo seu "
                + "texto visível, e as demais telas do Aplicativo não foram totalmente "
                + "testadas com um leitor de tela nem apenas com o teclado.",
            ]),
            Section(title: "Relatar problemas de acessibilidade", paragraphs: [
                "Se você encontrar uma barreira de acessibilidade no Aplicativo, descreva "
                + "por favor o problema e onde o encontrou, e envie essa descrição para "
                + "\(contactEmail).",
                "O Operador leva esses relatos a sério e os usa para decidir o que "
                + "corrigir em seguida.",
            ]),
            contactPT("esta Declaração de Acessibilidade"),
        ])
}
