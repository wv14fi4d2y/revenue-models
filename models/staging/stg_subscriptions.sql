{{
  config(
    materialized='view',
    tags=['staging', 'daily']
  )
}}

with source as (

    select * from {{ source('billing', 'subscriptions') }}

),

renamed as (

    select
        subscription_id,
        account_id,
        plan_id,
        cast(started_at as date)  as started_on,
        cast(canceled_at as date) as canceled_on,
        cast(mrr_cents as integer) as mrr_cents,
        lower(trim(status))       as status,
        cast(updated_at as timestamp) as updated_at

    from source

)

select * from renamed
