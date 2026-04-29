-- Public business tables are only used by signed-in Supabase users.
-- Keep existing policy predicates, but narrow evaluation from PUBLIC to
-- authenticated to reduce exposed surface area and RLS overhead.

ALTER POLICY "space members can create dates" ON public.important_dates TO authenticated;
ALTER POLICY "space members can read dates" ON public.important_dates TO authenticated;
ALTER POLICY "space members can update dates" ON public.important_dates TO authenticated;

ALTER POLICY "space members can create periodic" ON public.periodic_tasks TO authenticated;
ALTER POLICY "space members can read periodic" ON public.periodic_tasks TO authenticated;
ALTER POLICY "space members can update periodic" ON public.periodic_tasks TO authenticated;

ALTER POLICY "space members can read subtasks" ON public.project_subtasks TO authenticated;
ALTER POLICY "space members can write subtasks" ON public.project_subtasks TO authenticated;

ALTER POLICY "space members can create projects" ON public.projects TO authenticated;
ALTER POLICY "space members can read projects" ON public.projects TO authenticated;
ALTER POLICY "space members can update projects" ON public.projects TO authenticated;

ALTER POLICY "authenticated can create spaces" ON public.spaces TO authenticated;
ALTER POLICY "owner can read own spaces" ON public.spaces TO authenticated;
ALTER POLICY "owner can update space" ON public.spaces TO authenticated;
ALTER POLICY "space members can read spaces" ON public.spaces TO authenticated;

ALTER POLICY "space members can create lists" ON public.task_lists TO authenticated;
ALTER POLICY "space members can read lists" ON public.task_lists TO authenticated;
ALTER POLICY "space members can update lists" ON public.task_lists TO authenticated;

ALTER POLICY "can read messages of accessible tasks" ON public.task_messages TO authenticated;
ALTER POLICY "space members can insert task messages" ON public.task_messages TO authenticated;

ALTER POLICY "space members can create tasks" ON public.tasks TO authenticated;
ALTER POLICY "space members can read tasks" ON public.tasks TO authenticated;
ALTER POLICY "space members can update tasks" ON public.tasks TO authenticated;
