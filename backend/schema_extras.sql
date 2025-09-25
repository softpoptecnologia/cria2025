-- View de totais por sessão
CREATE OR REPLACE VIEW vw_totais_sessao AS
SELECT s.id AS sessao_id,
       COALESCE(SUM(l.contagem_incremental), 0) AS total
FROM sessoes_producao s
LEFT JOIN leituras l ON l.sessao_id = s.id
GROUP BY s.id;

-- Índice composto (acelera inserts/consultas por sessão/tempo)
CREATE INDEX IF NOT EXISTS idx_leituras_sessao_ts
ON leituras (sessao_id, timestamp);
