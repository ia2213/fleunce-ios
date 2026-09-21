-- Apply after migrations and the baseline runtime grants, as the migration owner.
REVOKE ALL ON minute_purchase_orders,minute_purchase_events,minute_purchase_transactions FROM fleunce_runtime;
GRANT SELECT,INSERT ON minute_purchase_orders,minute_purchase_events TO fleunce_runtime;
GRANT SELECT,INSERT ON minute_purchase_transactions TO fleunce_runtime;
GRANT UPDATE(state,granted_ms,refunded_minor,reversal_target_ms,recovered_ms,updated_at)
ON minute_purchase_transactions TO fleunce_runtime;
