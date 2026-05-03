alter table public.tasks
add column if not exists sort_order double precision not null default 0;

with ranked as (
    select
        id,
        row_number() over (
            partition by
                space_id,
                coalesce(list_id, '00000000-0000-0000-0000-000000000000'::uuid),
                coalesce(project_id, '00000000-0000-0000-0000-000000000000'::uuid),
                coalesce(date_trunc('day', due_at), date_trunc('day', created_at)),
                is_archived
            order by
                is_pinned desc,
                due_at asc nulls last,
                created_at asc,
                id asc
        )::double precision as next_sort_order
    from public.tasks
    where is_deleted = false
)
update public.tasks as t
set sort_order = ranked.next_sort_order
from ranked
where t.id = ranked.id
  and t.sort_order = 0;

create index if not exists idx_tasks_space_sort_order
on public.tasks(space_id, sort_order)
where is_deleted = false;
