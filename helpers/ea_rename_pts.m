function ea_rename_pts(BIDSRoot, oldSubjId, newSubjId, opts)
% Function to rename subj in a BIDS dataset
arguments
    BIDSRoot            {mustBeFolder}
    oldSubjId           {mustBeText}
    newSubjId           {mustBeText}
    opts.blindRename    {mustBeNumericOrLogical} = false;  % Blindy rename all files no matter if oldSubjId matches or not.
end

if ~iscell(oldSubjId)
    oldSubjId = {oldSubjId};
end

if ~iscell(newSubjId)
    newSubjId = {newSubjId};
end

if numel(oldSubjId) ~= numel(newSubjId)
    error('Length of old subjID doesn''t match length of new subjID!');
end

bids = BIDSFetcher(BIDSRoot);

if ~all(ismember(oldSubjId, bids.subjId))
    error('Not all the old subjID exist in the BIDS dataset!');
end

if numel(oldSubjId) ~= numel(unique(oldSubjId)) || numel(newSubjId) ~= numel(unique(newSubjId))
    error('Duplicated subjID found!');
end

if any(ismember(newSubjId, bids.subjId))
    error('New subjID conflicts with existing subjID in the BIDS dataset!');
end

for i = 1:numel(oldSubjId)
    old = oldSubjId{i};
    new = newSubjId{i};
    ea_cprintf('*Comment', 'Renaming subj %s to %s ...\n', old, new);

    parentDirs = {fullfile(BIDSRoot, 'derivatives', 'leaddbs'), ...
                  fullfile(BIDSRoot, 'rawdata'), ...
                  fullfile(BIDSRoot, 'sourcedata')};

    movedDirs = {};
    try
        for d = 1:numel(parentDirs)
            if isfolder(fullfile(parentDirs{d}, ['sub-', old]))
                moveSubjDir(parentDirs{d}, ['sub-', old], ['sub-', new]);
                movedDirs{end+1} = parentDirs{d};
            end
        end
    catch ME
        % Undo the folders which were already renamed, so that a failure never
        % leaves the subj split over two subjIDs.
        for d = 1:numel(movedDirs)
            try
                moveSubjDir(movedDirs{d}, ['sub-', new], ['sub-', old]);
            catch
                ea_cprintf('CmdWinErrors', 'Failed to roll back "%s"!\n', ...
                           fullfile(movedDirs{d}, ['sub-', new]));
            end
        end
        rethrow(ME);
    end

    if ~opts.blindRename
        oldFiles = ea_regexpdir(BIDSRoot, ['^sub-', old, '_']);
        newFiles = replace(oldFiles, [filesep, 'sub-', old, '_'], [filesep, 'sub-', new, '_']);
    else
        oldDerivativeFiles = ea_regexpdir(fullfile(BIDSRoot, 'derivatives', 'leaddbs', ['sub-', new]), '^sub-[^\W_]+_');
        newDerivativeFiles = replace(oldDerivativeFiles, filesep + "sub-" + alphanumericsPattern, [filesep, 'sub-', new]);
        oldRawFiles = ea_regexpdir(fullfile(BIDSRoot, 'rawdata', ['sub-', new]), '^sub-[^\W_]+_');
        newRawFiles = replace(oldRawFiles, filesep + "sub-" + alphanumericsPattern, [filesep, 'sub-', new]);
        oldSourceFiles = ea_regexpdir(fullfile(BIDSRoot, 'sourcedata', ['sub-', new]), '^sub-[^\W_]+_');
        newSourceFiles = replace(oldSourceFiles, filesep + "sub-" + alphanumericsPattern, [filesep, 'sub-', new]);
        oldFiles = [oldDerivativeFiles; oldRawFiles; oldSourceFiles];
        newFiles = [newDerivativeFiles; newRawFiles; newSourceFiles];
    end
    
    cellfun(@(src, dst) ~strcmp(src, dst) && movefile(src, dst), oldFiles, newFiles);

    rawImageJson = fullfile(BIDSRoot, 'derivatives', 'leaddbs', ['sub-', new], 'prefs', ['sub-', new, '_desc-rawimages.json']);
    if isfile(rawImageJson)
        json = fread(fopen(rawImageJson, 'rt'));
        if ~opts.blindRename
            json = replace(char(json'), ['sub-', old, '_'], ['sub-', new, '_']);
        else
            json = replace(char(json'), "sub-" + alphanumericsPattern + "_", ['sub-', new, '_']);
        end
        fwrite(fopen(rawImageJson, 'wt'), json);
    end

    statsFile = fullfile(BIDSRoot, 'derivatives', 'leaddbs', ['sub-', new], ['sub-', new, '_desc-stats.mat']);
    if isfile(statsFile)
        load(statsFile, 'ea_stats');
        if ~opts.blindRename
            ea_stats.patname = replace(ea_stats.patname, ['sub-', old], ['sub-', new]);
        else
            ea_stats.patname = replace(ea_stats.patname, "sub-" + alphanumericsPattern, ['sub-', new]);
        end
        save(statsFile, 'ea_stats');
    end

    statsBackupFile = fullfile(BIDSRoot, 'derivatives', 'leaddbs', ['sub-', new], ['sub-', new, '_desc-statsbackup.mat']);
    if isfile(statsBackupFile)
        load(statsBackupFile, 'ea_stats');
        if ~opts.blindRename
            ea_stats.patname = replace(ea_stats.patname, ['sub-', old], ['sub-', new]);
        else
            ea_stats.patname = replace(ea_stats.patname, "sub-" + alphanumericsPattern, ['sub-', new]);
        end
        save(statsBackupFile, 'ea_stats');
    end
end


function moveSubjDir(parentDir, oldName, newName)
% Rename a subj folder in place.
%
% Prefer an atomic rename (a single rename() syscall): it is instant and,
% unlike MATLAB's movefile (which copies the tree recursively), it never
% enumerates the folder. That matters on exFAT/FAT/SMB volumes, where macOS
% keeps xattrs in AppleDouble sidecars ('._*') which the kernel creates and
% removes implicitly while a sibling is copied, invalidating the listing
% mid-walk. Fall back to movefile for genuine cross-volume moves.

src = fullfile(parentDir, oldName);
dst = fullfile(parentDir, newName);

if isfolder(dst)
    error('Destination folder "%s" already exists!', dst);
end

renamed = false;
if usejava('jvm')
    renamed = java.io.File(src).renameTo(java.io.File(dst));
end

if ~renamed
    [status, msg] = movefile(src, dst);
    if ~status
        error(['Failed to move "%s" to "%s": %s\n', ...
               'The destination may be partially written, check it before retrying.'], ...
              src, dst, msg);
    end
end

if ~isfolder(dst) || isfolder(src)
    error('Move of "%s" to "%s" did not complete!', src, dst);
end

% Drop the AppleDouble sidecar of the old folder in case macOS didn't carry it over
if ismac
    ea_delete(fullfile(parentDir, ['._', oldName]));
end
