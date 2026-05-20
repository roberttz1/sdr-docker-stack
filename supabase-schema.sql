-- =============================================
-- SDR IA Elite — Schema Completo do Banco de Dados
-- Supabase (PostgreSQL)
-- Executar no SQL Editor do Supabase
-- =============================================

-- =============================================
-- 1. TABELA DE LEADS (núcleo do CRM)
-- =============================================
CREATE TABLE IF NOT EXISTS leads (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    telefone TEXT NOT NULL UNIQUE,
    nome_contato TEXT,                -- Pode ser NULL (SDR captura depois)
    nome_empresa TEXT,
    segmento TEXT,                    -- Ex: 'clinica', 'imobiliaria', 'loja'
    cidade TEXT,
    origem TEXT,                      -- Ex: 'google_maps', 'instagram', 'indicacao'
    observacao TEXT,
    status TEXT DEFAULT 'PENDENTE' CHECK (status IN (
        'PENDENTE',       -- Aguardando primeiro contato
        'ABORDADO',       -- Primeira mensagem enviada
        'EM_CONVERSA',    -- Lead respondeu, conversa ativa
        'INTERESSADO',    -- Lead demonstrou interesse
        'AGENDADO',       -- Reunião agendada
        'CONVERTIDO',     -- Virou cliente
        'RECUSADO',       -- Disse não
        'SEM_RESPOSTA',   -- Não respondeu após follow-ups
        'ERRO'            -- Erro técnico no envio
    )),
    motivo_recusa TEXT,               -- Preenchido quando status = RECUSADO
    data_primeiro_contato TIMESTAMPTZ,
    data_ultimo_contato TIMESTAMPTZ,
    proximo_followup TIMESTAMPTZ,     -- Quando o n8n deve recontatar
    total_mensagens_enviadas INT DEFAULT 0,
    total_mensagens_recebidas INT DEFAULT 0,
    follow_up_count INT DEFAULT 0,
    nome_capturado BOOLEAN DEFAULT FALSE,  -- Flag: o SDR já capturou o nome?
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Índices para performance
CREATE INDEX IF NOT EXISTS idx_leads_status ON leads(status);
CREATE INDEX IF NOT EXISTS idx_leads_telefone ON leads(telefone);
CREATE INDEX IF NOT EXISTS idx_leads_proximo_followup ON leads(proximo_followup);
CREATE INDEX IF NOT EXISTS idx_leads_segmento ON leads(segmento);

-- =============================================
-- 2. TABELA DE MENSAGENS (histórico completo)
-- =============================================
CREATE TABLE IF NOT EXISTS mensagens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lead_id UUID NOT NULL REFERENCES leads(id) ON DELETE CASCADE,
    direcao TEXT NOT NULL CHECK (direcao IN ('ENVIADA', 'RECEBIDA')),
    conteudo TEXT NOT NULL,
    remetente TEXT NOT NULL,          -- 'LETICIA_SDR' ou 'LEAD' ou 'GABRIEL'
    tipo_mensagem TEXT DEFAULT 'texto' CHECK (tipo_mensagem IN (
        'texto', 'primeiro_contato', 'follow_up', 'agendamento',
        'encerramento', 'transferencia'
    )),
    metadata JSONB DEFAULT '{}',     -- Dados extras (ex: segmento usado, prompt version)
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_mensagens_lead_id ON mensagens(lead_id);
CREATE INDEX IF NOT EXISTS idx_mensagens_created_at ON mensagens(created_at DESC);

-- =============================================
-- 3. TABELA DE AGENDAMENTOS
-- =============================================
CREATE TABLE IF NOT EXISTS agendamentos (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    lead_id UUID NOT NULL REFERENCES leads(id) ON DELETE CASCADE,
    data_hora TIMESTAMPTZ NOT NULL,
    duracao_minutos INT DEFAULT 30,
    status TEXT DEFAULT 'CONFIRMADO' CHECK (status IN (
        'CONFIRMADO', 'CANCELADO', 'REMARCADO', 'REALIZADO', 'NO_SHOW'
    )),
    link_reuniao TEXT,
    calcom_booking_id TEXT,           -- ID do Cal.com para sync
    observacoes_pre_reuniao TEXT,     -- Resumo da dor do lead
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_agendamentos_lead_id ON agendamentos(lead_id);
CREATE INDEX IF NOT EXISTS idx_agendamentos_data_hora ON agendamentos(data_hora);

-- =============================================
-- 4. TABELA DE MÉTRICAS DIÁRIAS (dashboard)
-- =============================================
CREATE TABLE IF NOT EXISTS metricas_diarias (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    data DATE NOT NULL UNIQUE,
    leads_abordados INT DEFAULT 0,
    respostas_recebidas INT DEFAULT 0,
    interessados INT DEFAULT 0,
    agendamentos INT DEFAULT 0,
    recusas INT DEFAULT 0,
    sem_resposta INT DEFAULT 0,
    taxa_resposta DECIMAL(5,2) DEFAULT 0,
    taxa_conversao DECIMAL(5,2) DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_metricas_data ON metricas_diarias(data DESC);

-- =============================================
-- 5. TABELA DE CONFIGURAÇÃO POR CLIENTE/SEGMENTO
-- =============================================
CREATE TABLE IF NOT EXISTS configuracoes_segmento (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    segmento TEXT NOT NULL UNIQUE,    -- Ex: 'clinica', 'imobiliaria', 'loja'
    nome_fantasia TEXT,               -- Como a Letícia se refere ao tipo de negócio
    prompt_abertura TEXT,             -- Prompt customizado para primeiro contato
    prompt_followup TEXT,             -- Prompt customizado para follow-up
    gatilhos_interesse TEXT[],        -- Array de palavras que indicam interesse
    gatilhos_recusa TEXT[],           -- Array de palavras que indicam recusa
    intervalo_followup_horas INT DEFAULT 24,
    max_followups INT DEFAULT 3,
    horario_inicio TIME DEFAULT '08:00',
    horario_fim TIME DEFAULT '18:00',
    dias_ativos INT[] DEFAULT '{1,2,3,4,5}',  -- 1=seg, 5=sex
    ativo BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- =============================================
-- 6. TABELA DE ANÁLISE DO MENTOR (Fase 3)
-- =============================================
CREATE TABLE IF NOT EXISTS analises_mentor (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    periodo_inicio DATE NOT NULL,
    periodo_fim DATE NOT NULL,
    total_conversas_analisadas INT DEFAULT 0,
    padroes_recusa JSONB DEFAULT '[]',
    sugestoes_melhoria JSONB DEFAULT '[]',
    pontuacao_eficiencia DECIMAL(5,2),
    relatorio_completo TEXT,
    aplicado BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- =============================================
-- 7. FUNCTION: Atualizar updated_at automaticamente
-- =============================================
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Triggers para auto-update
CREATE TRIGGER update_leads_updated_at
    BEFORE UPDATE ON leads
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_agendamentos_updated_at
    BEFORE UPDATE ON agendamentos
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_configuracoes_updated_at
    BEFORE UPDATE ON configuracoes_segmento
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- =============================================
-- 8. VIEWS para Dashboard (consultas prontas)
-- =============================================

-- View: Resumo do Pipeline (Kanban)
CREATE OR REPLACE VIEW vw_pipeline_kanban AS
SELECT
    status,
    COUNT(*) as total,
    COUNT(*) FILTER (WHERE data_ultimo_contato >= NOW() - INTERVAL '24 hours') as ativos_24h
FROM leads
GROUP BY status
ORDER BY
    CASE status
        WHEN 'PENDENTE' THEN 1
        WHEN 'ABORDADO' THEN 2
        WHEN 'EM_CONVERSA' THEN 3
        WHEN 'INTERESSADO' THEN 4
        WHEN 'AGENDADO' THEN 5
        WHEN 'CONVERTIDO' THEN 6
        WHEN 'RECUSADO' THEN 7
        WHEN 'SEM_RESPOSTA' THEN 8
        ELSE 9
    END;

-- View: KPIs Gerais
CREATE OR REPLACE VIEW vw_kpis_gerais AS
SELECT
    COUNT(*) as total_leads,
    COUNT(*) FILTER (WHERE status = 'CONVERTIDO') as convertidos,
    COUNT(*) FILTER (WHERE status = 'AGENDADO') as agendados,
    COUNT(*) FILTER (WHERE status = 'INTERESSADO') as interessados,
    COUNT(*) FILTER (WHERE status = 'RECUSADO') as recusados,
    ROUND(
        COUNT(*) FILTER (WHERE status IN ('INTERESSADO', 'AGENDADO', 'CONVERTIDO'))::DECIMAL /
        NULLIF(COUNT(*) FILTER (WHERE status != 'PENDENTE'), 0) * 100, 2
    ) as taxa_conversao_percent,
    ROUND(
        COUNT(*) FILTER (WHERE total_mensagens_recebidas > 0)::DECIMAL /
        NULLIF(COUNT(*) FILTER (WHERE status != 'PENDENTE'), 0) * 100, 2
    ) as taxa_resposta_percent
FROM leads;

-- =============================================
-- 9. DADOS INICIAIS: Configurações de Segmento
-- =============================================
INSERT INTO configuracoes_segmento (segmento, nome_fantasia, prompt_abertura, gatilhos_interesse, gatilhos_recusa, intervalo_followup_horas, max_followups) VALUES
(
    'clinica',
    'clínica',
    'Foco em: agenda cheia, tempo de resposta ao paciente, perda de pacientes para concorrente. Evitar termos técnicos de marketing. Falar em "pacientes" não "leads".',
    ARRAY['interessante', 'quero saber mais', 'como funciona', 'quanto custa', 'pode me explicar', 'agenda', 'marcar', 'reunião'],
    ARRAY['não preciso', 'não tenho interesse', 'para', 'não quero', 'remove', 'sai', 'já tenho'],
    24,
    3
),
(
    'imobiliaria',
    'imobiliária',
    'Foco em: velocidade de resposta ao comprador, qualificação de leads sérios vs curiosos, agendamento de visitas. Falar em "compradores" e "fechamento".',
    ARRAY['interessante', 'quero saber mais', 'como funciona', 'quanto custa', 'pode me explicar', 'marcar', 'reunião', 'visita'],
    ARRAY['não preciso', 'não tenho interesse', 'para', 'não quero', 'remove', 'sai', 'já tenho'],
    24,
    3
),
(
    'loja',
    'loja',
    'Foco em: recuperação de clientes inativos, aumento de ticket médio, atendimento rápido no WhatsApp. Falar em "clientes" e "faturamento".',
    ARRAY['interessante', 'quero saber mais', 'como funciona', 'quanto custa', 'pode me explicar', 'marcar', 'reunião'],
    ARRAY['não preciso', 'não tenho interesse', 'para', 'não quero', 'remove', 'sai', 'já tenho'],
    24,
    3
),
(
    'servicos',
    'empresa de serviços',
    'Foco em: prospecção ativa, qualificação antes do orçamento, follow-up para fechamento. Falar em "oportunidades" e "propostas".',
    ARRAY['interessante', 'quero saber mais', 'como funciona', 'quanto custa', 'pode me explicar', 'marcar', 'reunião', 'proposta', 'orçamento'],
    ARRAY['não preciso', 'não tenho interesse', 'para', 'não quero', 'remove', 'sai', 'já tenho'],
    24,
    3
);
