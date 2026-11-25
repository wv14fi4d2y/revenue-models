{{
  config(
    materialized='table',
    tags=['finance', 'metric'],
    unique_key=['account_id', 'month_start']
  )
}}

-- grain: one row per account_id per month_start (first day of month, UTC)
-- recognition: straight line across the invoice period, days prorated

with invoice_lines as (

    select * from {{ ref('stg_invoice_lines') }}
    where subscription_id is not null

),

expanded_days as (

    select
        il.invoice_line_id,
        il.account_id,
        il.subscription_id,
        il.period_start,
        il.period_end,
        il.amount_cents,
        day::date as revenue_date
    from invoice_lines il
    cross join lateral generate_series(
        il.period_start,
        il.period_end - 1,
        interval '1 day'
    ) as day

),

daily_amounts as (

    select
        invoice_line_id,
        account_id,
        subscription_id,
        revenue_date,
        -- integer cents per day, kept numeric so proration does not truncate
        amount_cents::numeric
            / nullif((period_end - period_start), 0) as daily_amount_cents
    from expanded_days

)

select
    account_id,
    date_trunc('month', revenue_date)::date as month_start,
    sum(daily_amount_cents)                 as recognized_revenue_cents,
    count(distinct revenue_date)            as days_with_revenue,
    count(distinct subscription_id)         as subscriptions_billed
from daily_amounts
group by 1, 2
