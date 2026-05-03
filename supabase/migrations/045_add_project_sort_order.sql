alter table public.projects
add column if not exists sort_order double precision not null default 0;

with ranked as (
    select
        id,
        row_number() over (
            partition by space_id, status, is_deleted
            order by
                updated_at desc,
                created_at asc,
                id asc
        )::double precision as next_sort_order
    from public.projects
    where is_deleted = false
)
update public.projects as p
set sort_order = ranked.next_sort_order
from ranked
where p.id = ranked.id
  and p.sort_order = 0;

create index if not exists idx_projects_space_sort_order
on public.projects(space_id, sort_order)
where is_deleted = false;
