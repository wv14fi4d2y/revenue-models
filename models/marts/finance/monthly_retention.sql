{{
  config(
    materialized='table',
    tags=['finance', 'metric'],
    unique_key=['month_start']
  )
}}

-- grain: one row per month_start
-- input grain: account-month, consecutive months only (gap months are not comparable)
-- nrr = (base + expansion - contraction - churn) / base, rounded to 4 decimals

with revenue as (

    select
        account_id,
        month_start,
        recognized_revenue_cents
    from {{ ref('subscription_revenue') }}

),

with_prior as (

    select
        account_id,
        month_start,
        recognized_revenue_cents as current_cents,
        lag(month_start) over w                as prior_month_start,
        lag(recognized_revenue_cents) over w   as prior_cents
    from revenue
    window w as (partition by account_id order by month_start)

),

consecutive as (

    select *
    from with_prior
    -- only month-over-month pairs; a missing month would be read as churn otherwise
    where prior_month_start is not null
      and (prior_month_start + interval '1 month')::date = month_start

),

movements as (

    select
        account_id,
        month_start,
        prior_cents,
        current_cents,
        case
            when prior_cents = 0 and current_cents > 0 then 'new'
            when current_cents = 0                     then 'churn'
            when current_cents > prior_cents           then 'expansion'
            when current_cents < prior_cents           then 'contraction'
            else 'flat'
        end as movement_type
    from consecutive

)

select
    month_start,
    sum(case when movement_type <> 'new' then prior_cents end)                  as base_cents,
    sum(case when movement_type = 'expansion' then current_cents - prior_cents end) as expansion_cents,
    sum(case when movement_type = 'contraction' then prior_cents - current_cents end) as contraction_cents,
    sum(case when movement_type = 'churn' then prior_cents end)                 as churn_cents,
    sum(current_cents)                                                          as ending_cents,
    round(
        (
            coalesce(sum(case when movement_type <> 'new' then prior_cents end), 0)
            + coalesce(sum(case when movement_type = 'expansion' then current_cents - prior_cents end), 0)
            - coalesce(sum(case when movement_type = 'contraction' then prior_cents - current_cents end), 0)
            - coalesce(sum(case when movement_type = 'churn' then prior_cents end), 0)
        )
        / nullif(sum(case when movement_type <> 'new' then prior_cents end), 0),
        4
    ) as net_revenue_retention
from movements
group by 1
