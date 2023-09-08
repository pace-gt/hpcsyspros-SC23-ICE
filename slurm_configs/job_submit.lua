function slurm_job_submit(job_desc, part_list, submit_uid)
  -- Make sure users don't provide email based on your_email or gburdell3 example username
  local mail_user = job_desc.mail_user
  if mail_user ~= nil then
    if (not string.find(mail_user,"@") or string.find(mail_user,"your_email") or string.find(mail_user,"gburdell3")) then
      slurm.log_user("Invalid email address provided. Please review --mail-user argument in job submission.")
      return 2036
    end
  end

  if job_desc.qos == nil then
    job_desc.qos = job_desc.default_qos
  end
  local tresString = ""
  if job_desc.tres_per_job ~= nil then
    tresString = tresString .. tostring(job_desc.tres_per_job)
  end
  if job_desc.tres_per_node ~= nil then
    tresString = tresString .. tostring(job_desc.tres_per_node)
  end
  if job_desc.tres_per_socket ~= nil then
     tresString = tresString .. tostring(job_desc.tres_per_socket)
  end
  if job_desc.tres_per_task ~= nil then
    tresString = tresString .. tostring(job_desc.tres_per_task)
  end
  if job_desc.partition == nil then
    if (string.find(tostring(job_desc.qos),"coc")) then
      if (string.find(tresString,"gpu")) then
        job_desc.partition = "coc-gpu,ice-gpu"
      else
        job_desc.partition = "coc-cpu,ice-cpu"
      end
    else
      if (string.find(tresString,"gpu")) then
        job_desc.partition = "pace-gpu,ice-gpu"
      else
        job_desc.partition = "pace-cpu,ice-cpu"
      end
    end
  end
  return slurm.SUCCESS
end

function slurm_job_modify(job_desc, job_rec, part_list, modify_uid)
  local tresString = ""
  if job_desc.tres_per_job ~= nil then
    tresString = tresString .. tostring(job_desc.tres_per_job)
  end
  if job_desc.tres_per_node ~= nil then
    tresString = tresString .. tostring(job_desc.tres_per_node)
  end
  if job_desc.tres_per_socket ~= nil then
     tresString = tresString .. tostring(job_desc.tres_per_socket)
  end
  if job_desc.tres_per_task ~= nil then
    tresString = tresString .. tostring(job_desc.tres_per_task)
  end
  if job_desc.partition == nil then
    if (string.find(tostring(job_desc.qos),"coc")) then
      if (string.find(tresString,"gpu")) then
        if not (string.find(tresString,"[Mm][Ii]210") or string.find(featString,"[Mm][Ii]210") or string.find(featString,"amd-gpu")) then
          job_desc.features = 
        job_desc.partition = "coc-gpu,ice-gpu"
      else
        job_desc.partition = "coc-cpu,ice-cpu"
      end
    else
      if (string.find(tresString,"gpu")) then
        job_desc.partition = "pace-gpu,ice-gpu"
      else
        job_desc.partition = "pace-cpu,ice-cpu"
      end
    end
  end
  return slurm.SUCCESS
end

return slurm.SUCCESS
