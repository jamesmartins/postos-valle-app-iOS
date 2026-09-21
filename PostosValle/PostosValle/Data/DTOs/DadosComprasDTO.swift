import Foundation

struct DadosComprasResponseDTO: Codable {
    let msgerro: String
    let coderro: FlexibleInt
    let cliente: DadosComprasClienteDTO?
    let saldo: DadosComprasSaldoDTO?
    let compras: [DadosComprasMovimentoDTO]?
}

struct DadosComprasClienteDTO: Codable {
    let codigoCliente: FlexibleInt
    let nome: String
    let primeiroNome: String?
    let numCgcecpf: String
    let cartao: String?
    let email: String?
    let celular: String?
    let ativo: Bool?

    enum CodingKeys: String, CodingKey {
        case codigoCliente = "codigo_cliente"
        case nome
        case primeiroNome = "primeiro_nome"
        case numCgcecpf = "num_cgcecpf"
        case cartao, email, celular, ativo
    }

    func toDomain() -> Cliente {
        Cliente(
            codigoCliente: codigoCliente.value,
            nome: nome,
            primeiroNome: primeiroNome,
            numCgcecpf: numCgcecpf,
            cartao: cartao,
            email: email,
            celular: celular,
            ativo: ativo
        )
    }
}

struct DadosComprasSaldoDTO: Codable {
    let unidade: String?
    let disponivel: FlexibleDouble
    let resgatado: FlexibleDouble
    let expirado: FlexibleDouble
    let ganho: FlexibleDouble?
    let aLiberar: FlexibleDouble?
    let bloqueado: FlexibleDouble?

    enum CodingKeys: String, CodingKey {
        case unidade, disponivel, resgatado, expirado, ganho
        case aLiberar = "a_liberar"
        case bloqueado
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        unidade = try container.decodeIfPresent(String.self, forKey: .unidade)
        disponivel = try container.decodeIfPresent(FlexibleDouble.self, forKey: .disponivel) ?? FlexibleDouble(0)
        resgatado = try container.decodeIfPresent(FlexibleDouble.self, forKey: .resgatado) ?? FlexibleDouble(0)
        expirado = try container.decodeIfPresent(FlexibleDouble.self, forKey: .expirado) ?? FlexibleDouble(0)
        ganho = try container.decodeIfPresent(FlexibleDouble.self, forKey: .ganho)
        aLiberar = try container.decodeIfPresent(FlexibleDouble.self, forKey: .aLiberar)
        bloqueado = try container.decodeIfPresent(FlexibleDouble.self, forKey: .bloqueado)
    }

    func toDomain() -> Saldo {
        Saldo(
            unidade: unidade ?? "R$",
            disponivel: disponivel.value,
            resgatado: resgatado.value,
            expirado: expirado.value,
            ganho: ganho?.value ?? 0,
            aLiberar: aLiberar?.value ?? 0,
            bloqueado: bloqueado?.value ?? 0
        )
    }
}

struct DadosComprasMovimentoDTO: Codable {
    let codigoMovimento: FlexibleInt?
    let tipoMovimento: String?
    let lancamento: String?
    let ocorrencia: String?
    let unidade: String?
    let status: String?
    let dataMovimentoBr: String?
    let valores: DadosComprasValoresDTO?

    enum CodingKeys: String, CodingKey {
        case codigoMovimento = "codigo_movimento"
        case tipoMovimento = "tipo_movimento"
        case lancamento, ocorrencia, unidade, status
        case dataMovimentoBr = "data_movimento_br"
        case valores
    }

    func toDomain() -> MovimentoCompra {
        MovimentoCompra(
            id: codigoMovimento?.value ?? 0,
            tipoMovimento: tipoMovimento ?? "",
            lancamento: lancamento ?? "",
            ocorrencia: ocorrencia ?? "",
            unidade: unidade ?? "R$",
            status: status ?? "",
            dataMovimentoBr: dataMovimentoBr ?? "",
            valorVenda: valores?.venda.value ?? 0,
            valorCashback: valores?.cashbackOuPontos.value ?? 0
        )
    }
}

struct DadosComprasValoresDTO: Codable {
    let venda: FlexibleDouble
    let cashbackOuPontos: FlexibleDouble

    enum CodingKeys: String, CodingKey {
        case venda
        case cashbackOuPontos = "cashback_ou_pontos"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        venda = try container.decodeIfPresent(FlexibleDouble.self, forKey: .venda) ?? FlexibleDouble(0)
        cashbackOuPontos = try container.decodeIfPresent(FlexibleDouble.self, forKey: .cashbackOuPontos) ?? FlexibleDouble(0)
    }
}
