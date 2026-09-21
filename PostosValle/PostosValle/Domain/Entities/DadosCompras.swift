import Foundation

struct Cliente: Equatable {
    let codigoCliente: Int
    let nome: String
    let primeiroNome: String?
    let numCgcecpf: String
    let cartao: String?
    let email: String?
    let celular: String?
    let ativo: Bool?
}

struct Saldo: Equatable {
    let unidade: String
    let disponivel: Double
    let resgatado: Double
    let expirado: Double
    let ganho: Double
    let aLiberar: Double
    let bloqueado: Double
}

struct MovimentoCompra: Identifiable, Equatable {
    let id: Int
    let tipoMovimento: String
    let lancamento: String
    let ocorrencia: String
    let unidade: String
    let status: String
    let dataMovimentoBr: String
    let valorVenda: Double
    let valorCashback: Double
}

struct DadosComprasDashboard: Equatable {
    let cliente: Cliente?
    let saldo: Saldo?
    let compras: [MovimentoCompra]
}
