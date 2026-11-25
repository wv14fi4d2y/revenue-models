{{
  config(
    materialized='view',
    tags=['staging', 'daily']
  )
}}

with source as (

    select * from {{ source('billing', 'invoice_lines') }}

),

valid_periods as (

    select
        invoice_line_id,
        invoice_id,
        account_id,
        subscription_id,
        cast(period_start as date) as period_start,
        cast(period_end as date)   as period_end,
        cast(amount_cents as integer) as amount_cents,
        cast(issued_at as timestamp)  as issued_at

    from source
    where period_start is not null
      and period_end is not null
      -- period_end is exclusive, so an empty window cannot be prorated
      and cast(period_end as date) > cast(period_start as date)
      and amount_cents is not null

)

select * from valid_periods
