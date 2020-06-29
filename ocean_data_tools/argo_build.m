
%  Author: Laur Ferris
%  Email address: lnferris@alum.mit.edu
%  Website: https://github.com/lnferris/ocean_data_tools
%  Jun 2020; Last revision: 27-Jun-2020
%  Distributed under the terms of the MIT License

function [argo,matching_files] = argo_build(argo_dir,region,start_date,end_date,variable_list)

    FillValue = 99999; % From Argo manual.
    start_date = datenum(start_date,'dd-mmm-yyyy HH:MM:SS');
    end_date = datenum(end_date,'dd-mmm-yyyy HH:MM:SS');
    slim = region(1); nlim = region(2);  % Unpack SearchLimits.
    wlim = region(3); elim = region(4);

    base_list = {'PLATFORM_NUMBER','LONGITUDE','LATITUDE','JULD','PRES_ADJUSTED'}; % Variables automatically included.
    variable_list(ismember(variable_list, base_list )) = []; % remove redundant vars
    variable_list = [base_list variable_list];
    nvar = length(variable_list);
    nbase = length(base_list);
    
    matching_files = []; % Make an empty list to hold filenames.
    argo_cell = cell(0,nvar); % Make an empty table to hold profile data.
    full_path = dir(argo_dir);
    
    for i = 1:length(full_path) % For each file in full_path...
        filename = [full_path(i).folder '/' full_path(i).name];
        nc = netcdf.open(filename, 'NOWRITE'); % Open the file as a netcdf datasource.
        
         try % Try to read the file.
            cast_cell = cell(1,nvar);

            VAR1 = str2num(netcdf.getVar(nc,netcdf.inqVarID(nc,'PLATFORM_NUMBER')).'); % ID
            VAR2 = netcdf.getVar(nc,netcdf.inqVarID(nc,'LONGITUDE'));
            VAR3 = netcdf.getVar(nc,netcdf.inqVarID(nc,'LATITUDE'));
            VAR4 = netcdf.getVar(nc,netcdf.inqVarID(nc,'JULD'))+ datenum(1950,1,1); %Argo date  is days since 1950-01-01.
            VAR5 = netcdf.getVar(nc,netcdf.inqVarID(nc,'PRES_ADJUSTED'));
            
            % See which profiles have the correct lat,lon,date.
            good_inds = find(VAR3 >= slim & VAR3 <= nlim & VAR2 >= wlim & VAR2 <= elim & VAR4 >= start_date & VAR4 < (end_date +1));
             
            if any(good_inds) % If there is at least one good profile in this file...
                for cast = 1:length(good_inds) % Write each good profile into temporary cell array...
                    
                    if ~all(VAR5(:,good_inds(cast)) == FillValue) && length(find(VAR5(:,good_inds(cast))~=FillValue))>1 % As long is profile is not just fill values.
                        matching_files = [matching_files; string(filename)]; % Record filename to list.

                        cast_cell{1} = VAR1(good_inds(cast));
                        cast_cell{2} = VAR2(good_inds(cast));
                        cast_cell{3} = VAR3(good_inds(cast));
                        cast_cell{4} = VAR4(good_inds(cast));
                        cast_cell{5} = VAR5(:,good_inds(cast));
                        for var = nbase+1:nvar
                            VAR = netcdf.getVar(nc,netcdf.inqVarID(nc,variable_list{var}));
                            cast_cell{var} = VAR(:,good_inds(cast));
                        end
                        argo_cell = [argo_cell;cast_cell]; % Combine temporary cell array with general datatable.
                    end
                end
            end

         catch ME % Throw an exception if unable to read file.
            ME;
            disp(['Cannot read ',filename]);
         end    
    netcdf.close(nc); % Close the file.
    end
    
    % find necessary array dimensions
    [sz1,sz2] = cellfun(@size,argo_cell);
    z_dim = max(max([sz1,sz2]));
    prof_dim = size(argo_cell,1);
    var_dim = size(argo_cell,2);
    is_matrix = sz1(1,:)~=1;

    % load data into structured array
    argo.stn = 1:prof_dim;
    for var = 1:var_dim
        variable = variable_list{var};
        if is_matrix(var)
            argo.(variable) = NaN(z_dim,prof_dim);
        else
            argo.(variable) = NaN(1,prof_dim);
        end 

        for prof = 1:prof_dim
            ind_last = sz1(prof,var);  
            dat = argo_cell(prof,var);
            if is_matrix(var)
                argo.(variable)(1:ind_last,prof) = dat{:};
            else
                argo.(variable)(prof) = dat{:};
            end 
        end
    end

    % clean out fills
    fns = fieldnames(argo);
    for i = 1:length(fns)  
        field = argo.(fns{i});
        argo.(fns{i})(field==FillValue) = NaN;
    end

    % rename the depth variable depth
    argo.depth = argo.PRES_ADJUSTED;
    argo.lon = argo.LONGITUDE;
    argo.lat = argo.LATITUDE;
    argo.date = argo.JULD;
    argo.id = argo.PLATFORM_NUMBER;
    fields = {'LONGITUDE','LATITUDE','JULD','PRES_ADJUSTED','PLATFORM_NUMBER'};
    argo = rmfield(argo,fields);

    % if working near dateline wrap to 0/360
    if min(argo.lon) < -170 && max(argo.lon)>170  
        argo.lon(argo.lon < 0) = argo.lon(argo.lon < 0)+360; 
    end 
    
end