function ea_screenshots(uipatdir,target)
% Wrapper of ea_screenshot used for exporting ZIP

options=ea_getptopts(uipatdir);
options.fiberthresh=1;
options.d3.verbose='on';
options.native=0;
options=ea_detsides(options);

[~,~,~,elmodel]=ea_load_reconstruction(options);
options.leadprod='dbs';
options.elmodel=elmodel;
options=ea_resolve_elspec(options);
options=ea_detsides(options);
options.d3.elrendering=1;
options.d3.hlactivecontacts=0;
options.d3.writeatlases=1;
options.d3.showisovolume=0;
viewsets=load([ea_getearoot,'helpers',filesep,'export',filesep,'ea_exportviews']);


options.atlasset=viewsets.(target).atlas;
options.sidecolor=1;
options.writeoutstats=0;

[options.root,options.patientname]=fileparts(options.subj.subjDir);
options.root=[options.root,filesep];
resultfig=ea_elvis(options);

if ~exist([options.root,options.patientname,filesep,'export',filesep,'views'],'dir')
    mkdir([options.root,options.patientname,filesep,'export',filesep,'views']);
end


views=viewsets.(target).views;

% delete generic lights:
RightLight=getappdata(resultfig,'RightLight');
LeftLight=getappdata(resultfig,'LeftLight');
CeilingLight=getappdata(resultfig,'CeilingLight');
CamLight=getappdata(resultfig,'CamLight');
delete(RightLight); delete(LeftLight); delete(CeilingLight); delete(CamLight);


% make view a bit flatter than usual:
ea_flatview(resultfig);
set(0,'CurrentFigure',resultfig);
hl=camlight('headlight');
ll=camlight('left');
rl=camlight('right');

el_render=getappdata(resultfig,'el_render');
eltext=getappdata(resultfig,'eltext');
sidestr={'right','left'};

cnt=1;
for view=[4,3,2,1,7:numel(views)] % views 5-6 are not exported, 7+ are optional extra views
    % optional per-view fields: side (1=right, 2=left, []=both) and labels (contact labels)
    side=[];
    if isfield(views,'side')
        side=views(view).side;
    end
    showlabels=view==3;
    if isfield(views,'labels')
        showlabels=views(view).labels;
    end

    % one hemisphere only: hide the atlas structures and electrode of the other side
    structures=views(view).structures;
    if ~isempty(side)
        structures=strcat(structures,'_',sidestr{side});
    end
    set(0,'CurrentFigure',resultfig);
    ea_keepatlaslabels(structures{:});
    if isa(el_render,'ea_trajectory')
        for el=1:numel(el_render)
            set(el_render(el).elpatch,'Visible',ea_bool2onoff(isempty(side) || el_render(el).side==side));
        end
    end
    set(0,'CurrentFigure',resultfig);
    ea_setplanes(views(view).planes.x,views(view).planes.y,views(view).planes.z);
    set(0,'CurrentFigure',resultfig);
    ea_view(views(view).v,resultfig);
    set(0,'CurrentFigure',resultfig);
    camlight(hl,'headlight');
    camlight(ll,'left');
    camlight(rl,'right');

    % text is drawn on top of everything, so only label the side that is shown
    labels=[];
    if showlabels && ~isempty(eltext)
        rows=1:size(eltext,1);
        if ~isempty(side)
            rows=intersect(rows,side);
        end
        labels=eltext(rows,:);
        labels=labels(isgraphics(labels));
    end
    set(labels,'Visible','on');
    drawnow
    ea_screenshot([options.root,options.patientname,filesep,'export',filesep,'views',filesep,'view_',sprintf('%03.0f',cnt),'.png'],'ld', resultfig);
    set(labels,'Visible','off');
    cnt=cnt+1;
end
 close(resultfig);
